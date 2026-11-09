package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/middleware"
	"backend/internal/models"
)

type DraftRequest struct {
	ImageBase64   string `json:"image_base64"`
	MainRole      string `json:"main_role"`
	SecondaryRole string `json:"secondary_role"`
	AutofillRole  string `json:"autofill_role"`
	Language      string `json:"language,omitempty"`
	GameMode      string `json:"game_mode,omitempty"` // "wild_rift" o "lol_pc"
}

type DraftResponse struct {
	Recommendation   string `json:"recommendation"`
	AvailableQueries int    `json:"available_queries"`
}

func noQueriesMessage(lang string) string {
	switch gemini.NormalizeLanguage(lang) {
	case "pt":
		return "Sem consultas disponíveis. Abra o Drafting e toque em 'Obter consultas'."
	case "en":
		return "No queries available. Open Drafting and tap 'Get queries'."
	case "fr":
		return "Aucune requête disponible. Ouvre Drafting et appuie sur 'Obtenir des requêtes'."
	default:
		return "Sin consultas disponibles. Abre Drafting y toca 'Obtener consultas'."
	}
}

func AnalyzeDraft(w http.ResponseWriter, r *http.Request) {
	var req DraftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.ImageBase64 == "" {
		http.Error(w, "image_base64 is required", http.StatusBadRequest)
		return
	}

	lang := strings.TrimSpace(req.Language)
	if lang == "" {
		lang = strings.TrimSpace(r.Header.Get("Accept-Language"))
	}
	lang = gemini.NormalizeLanguage(lang)

	// Retrieve user from context
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	// Sincronizar bono diario y recalcular saldo (incluso para usuarios con versiones anteriores o burbuja directa)
	today := time.Now().UTC().Format("2006-01-02")
	dailyGranted := user.RefreshDailyQueries(today)
	subExpired := user.CheckSubscriptionExpiry()
	user.RecalculateAvailableQueries()

	if dailyGranted || subExpired {
		database.DB.Model(user).Updates(map[string]interface{}{
			"daily_queries":          user.DailyQueries,
			"available_queries":      user.AvailableQueries,
			"last_daily_reward_date": user.LastDailyRewardDate,
			"subscription_plan":      user.SubscriptionPlan,
			"subscription_ends_at":   user.SubscriptionEndsAt,
		})
	}

	// --- Quota & Consultation Logic ---
	if user.AvailableQueries <= 0 {
		http.Error(w, noQueriesMessage(lang), http.StatusPaymentRequired)
		return
	}
	// -----------------------------------

	// Determine game mode (wild_rift o lol_pc)
	gameMode := strings.TrimSpace(strings.ToLower(req.GameMode))
	if gameMode == "" {
		gameMode = "wild_rift"
	}

	// Call Gemini API in the user's selected language (es, pt, en, fr) and game mode
	recommendation, tokens, err := gemini.AnalyzeDraft(
		r.Context(),
		req.ImageBase64,
		req.MainRole,
		req.SecondaryRole,
		req.AutofillRole,
		gameMode,
		lang,
	)
	if err != nil {
		log.Printf("AnalyzeDraft Error: %v", err)
		http.Error(w, fmt.Sprintf("Error al generar recomendación: %v", err), http.StatusInternalServerError)
		return
	}

	// Record successful API usage with tokens for cost tracking
	database.DB.Create(&models.ApiUsage{UserID: user.ID, TokensUsed: int(tokens), CreatedAt: time.Now()})

	// Decrement query count with priority (Daily -> Subscription -> Bonus -> Ad -> Purchased)
	user.ConsumeQuery()
	user.LastDraftAt = time.Now()
	database.DB.Model(user).Updates(map[string]interface{}{
		"daily_queries":          user.DailyQueries,
		"subscription_queries":   user.SubscriptionQueries,
		"bonus_queries":          user.BonusQueries,
		"ad_queries":             user.AdQueries,
		"purchased_queries":      user.PurchasedQueries,
		"available_queries":      user.AvailableQueries,
		"last_daily_reward_date": user.LastDailyRewardDate,
		"last_draft_at":          user.LastDraftAt,
	})

	// Send Response
	resp := DraftResponse{
		Recommendation:   recommendation,
		AvailableQueries: user.AvailableQueries,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
