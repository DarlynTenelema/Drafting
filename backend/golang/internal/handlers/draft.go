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
	"backend/internal/utils"
)

type DraftRequest struct {
	ImageBase64      string `json:"image_base64,omitempty"`
	DraftContext     string `json:"draft_context,omitempty"`
	MainRole         string `json:"main_role,omitempty"`
	SecondaryRole    string `json:"secondary_role,omitempty"`
	AutofillRole     string `json:"autofill_role,omitempty"`
	OtpChampions     string `json:"otp_champions,omitempty"`
	Language         string `json:"language,omitempty"`
	GameMode         string `json:"game_mode,omitempty"` // "wild_rift" o "lol_pc"
	ExcludeChampions string `json:"exclude_champions,omitempty"`
}

type ManualDraftRequest struct {
	MainRole         string `json:"main_role"`
	MyChampion       string `json:"my_champion,omitempty"`
	EnemyChampion    string `json:"enemy_champion"`
	Language         string `json:"language,omitempty"`
	GameMode         string `json:"game_mode,omitempty"` // "wild_rift" o "lol_pc"
	ExcludeChampions string `json:"exclude_champions,omitempty"`
}

type ChatDraftRequest struct {
	Message      string `json:"message"`
	DraftContext string `json:"draft_context,omitempty"`
	OtpChampions string `json:"otp_champions,omitempty"`
	Language     string `json:"language,omitempty"`
	GameMode     string `json:"game_mode,omitempty"`
}

type DraftResponse struct {
	Recommendation   string `json:"recommendation"`
	DraftContext     string `json:"draft_context,omitempty"`
	AvailableQueries int    `json:"available_queries"`
	BlockedByGuard   bool   `json:"blocked_by_guard,omitempty"`
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

func syncUserQuotaBeforeQuery(user *models.User) {
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
}

func deductUserQueryAndRecordUsage(user *models.User, tokens int32) {
	database.DB.Create(&models.ApiUsage{UserID: user.ID, TokensUsed: int(tokens), CreatedAt: time.Now()})

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
}

func AnalyzeDraft(w http.ResponseWriter, r *http.Request) {
	var req DraftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(req.ImageBase64) == "" && strings.TrimSpace(req.DraftContext) == "" {
		http.Error(w, "image_base64 or draft_context is required", http.StatusBadRequest)
		return
	}

	lang := strings.TrimSpace(req.Language)
	if lang == "" {
		lang = strings.TrimSpace(r.Header.Get("Accept-Language"))
	}
	lang = gemini.NormalizeLanguage(lang)

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	syncUserQuotaBeforeQuery(user)

	if user.AvailableQueries <= 0 {
		http.Error(w, noQueriesMessage(lang), http.StatusPaymentRequired)
		return
	}

	gameMode := strings.TrimSpace(strings.ToLower(req.GameMode))
	if gameMode == "" {
		gameMode = "wild_rift"
	}

	var (
		recommendation string
		draftContext   string
		tokens         int32
		err            error
	)

	// Si ya existe draft_context y NO se envía imagen nueva, ejecutar reconsulta ligera sin imagen (Punto 1.2 y 1.6)
	if strings.TrimSpace(req.ImageBase64) == "" && strings.TrimSpace(req.DraftContext) != "" {
		recommendation, draftContext, tokens, err = gemini.ReconsultDraftFromContext(
			r.Context(),
			req.DraftContext,
			req.OtpChampions,
			gameMode,
			lang,
			strings.TrimSpace(req.ExcludeChampions),
		)
	} else {
		recommendation, draftContext, tokens, err = gemini.AnalyzeDraft(
			r.Context(),
			req.ImageBase64,
			req.MainRole,
			req.SecondaryRole,
			req.AutofillRole,
			gameMode,
			req.OtpChampions,
			lang,
			strings.TrimSpace(req.ExcludeChampions),
		)
	}

	if err != nil {
		log.Printf("AnalyzeDraft Error: %v", err)
		http.Error(w, fmt.Sprintf("Error al generar recomendación: %v", err), http.StatusInternalServerError)
		return
	}

	deductUserQueryAndRecordUsage(user, tokens)

	resp := DraftResponse{
		Recommendation:   recommendation,
		DraftContext:     draftContext,
		AvailableQueries: user.AvailableQueries,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// ReconsultDraft maneja las reconsultas usando únicamente el contexto guardado de la primera captura (sin imagen)
func ReconsultDraft(w http.ResponseWriter, r *http.Request) {
	var req DraftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(req.DraftContext) == "" && strings.TrimSpace(req.ImageBase64) == "" {
		http.Error(w, "draft_context is required", http.StatusBadRequest)
		return
	}

	lang := strings.TrimSpace(req.Language)
	if lang == "" {
		lang = strings.TrimSpace(r.Header.Get("Accept-Language"))
	}
	lang = gemini.NormalizeLanguage(lang)

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	syncUserQuotaBeforeQuery(user)

	if user.AvailableQueries <= 0 {
		http.Error(w, noQueriesMessage(lang), http.StatusPaymentRequired)
		return
	}

	gameMode := strings.TrimSpace(strings.ToLower(req.GameMode))
	if gameMode == "" {
		gameMode = "wild_rift"
	}

	recommendation, draftContext, tokens, err := gemini.ReconsultDraftFromContext(
		r.Context(),
		req.DraftContext,
		req.OtpChampions,
		gameMode,
		lang,
		strings.TrimSpace(req.ExcludeChampions),
	)
	if err != nil {
		log.Printf("ReconsultDraft Error: %v", err)
		http.Error(w, fmt.Sprintf("Error al reconsultar alternativas: %v", err), http.StatusInternalServerError)
		return
	}

	deductUserQueryAndRecordUsage(user, tokens)

	resp := DraftResponse{
		Recommendation:   recommendation,
		DraftContext:     draftContext,
		AvailableQueries: user.AvailableQueries,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// ChatDraft maneja el nuevo sistema de Chatbot en tiempo real (Punto 1.8) con el Asistente Puente anti-insultos/links/50 palabras
func ChatDraft(w http.ResponseWriter, r *http.Request) {
	var req ChatDraftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	lang := strings.TrimSpace(req.Language)
	if lang == "" {
		lang = strings.TrimSpace(r.Header.Get("Accept-Language"))
	}
	lang = gemini.NormalizeLanguage(lang)

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	syncUserQuotaBeforeQuery(user)

	// 1. Asistente Puente: Validar groserías, siglas ofensivas (SPCRF), links y máximo 50 palabras ANTES de llegar a la IA
	if valid, guardMsg := utils.ValidateDraftChatMessage(req.Message, lang); !valid {
		resp := DraftResponse{
			Recommendation:   guardMsg,
			DraftContext:     req.DraftContext,
			AvailableQueries: user.AvailableQueries,
			BlockedByGuard:   true,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
		return
	}

	if user.AvailableQueries <= 0 {
		http.Error(w, noQueriesMessage(lang), http.StatusPaymentRequired)
		return
	}

	gameMode := strings.TrimSpace(strings.ToLower(req.GameMode))
	if gameMode == "" {
		gameMode = "wild_rift"
	}

	answer, tokens, err := gemini.AnalyzeDraftChat(
		r.Context(),
		strings.TrimSpace(req.Message),
		req.DraftContext,
		req.OtpChampions,
		gameMode,
		lang,
	)
	if err != nil {
		log.Printf("ChatDraft Error: %v", err)
		http.Error(w, fmt.Sprintf("Error en chat táctico: %v", err), http.StatusInternalServerError)
		return
	}

	deductUserQueryAndRecordUsage(user, tokens)

	resp := DraftResponse{
		Recommendation:   answer,
		DraftContext:     req.DraftContext,
		AvailableQueries: user.AvailableQueries,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func AnalyzeManualDraft(w http.ResponseWriter, r *http.Request) {
	var req ManualDraftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	enemyChamp := strings.TrimSpace(req.EnemyChampion)
	myChamp := strings.TrimSpace(req.MyChampion)
	mainRole := strings.TrimSpace(req.MainRole)
	if enemyChamp == "" && myChamp == "" {
		http.Error(w, "enemy_champion or my_champion is required", http.StatusBadRequest)
		return
	}
	if mainRole == "" {
		mainRole = "Mid"
	}

	lang := strings.TrimSpace(req.Language)
	if lang == "" {
		lang = strings.TrimSpace(r.Header.Get("Accept-Language"))
	}
	lang = gemini.NormalizeLanguage(lang)

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	syncUserQuotaBeforeQuery(user)

	if user.AvailableQueries <= 0 {
		http.Error(w, noQueriesMessage(lang), http.StatusPaymentRequired)
		return
	}

	gameMode := strings.TrimSpace(strings.ToLower(req.GameMode))
	if gameMode == "" {
		gameMode = "wild_rift"
	}

	recommendation, tokens, err := gemini.AnalyzeManualDraft(
		r.Context(),
		mainRole,
		myChamp,
		enemyChamp,
		gameMode,
		lang,
		strings.TrimSpace(req.ExcludeChampions),
	)
	if err != nil {
		log.Printf("AnalyzeManualDraft Error: %v", err)
		http.Error(w, fmt.Sprintf("Error al generar recomendación manual: %v", err), http.StatusInternalServerError)
		return
	}

	deductUserQueryAndRecordUsage(user, tokens)

	resp := DraftResponse{
		Recommendation:   recommendation,
		AvailableQueries: user.AvailableQueries,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
