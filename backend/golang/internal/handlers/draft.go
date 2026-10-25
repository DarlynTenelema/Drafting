package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
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
}

type DraftResponse struct {
	Recommendation string `json:"recommendation"`
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

	// Retrieve user from context
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	// --- Quota & Consultation Logic ---
	if user.AvailableQueries <= 0 {
		http.Error(w, "Sin consultas disponibles. Abre Drafting y toca 'Obtener consultas'.", http.StatusPaymentRequired)
		return
	}
	// -----------------------------------

	// Call Gemini API
	recommendation, tokens, err := gemini.AnalyzeDraft(r.Context(), req.ImageBase64, req.MainRole, req.SecondaryRole, req.AutofillRole)
	if err != nil {
		log.Printf("AnalyzeDraft Error: %v", err)
		http.Error(w, fmt.Sprintf("Error al generar recomendación: %v", err), http.StatusInternalServerError)
		return
	}

	// Record successful API usage with tokens for cost tracking
	database.DB.Create(&models.ApiUsage{UserID: user.ID, TokensUsed: int(tokens), CreatedAt: time.Now()})

	// Decrement query count with priority (Daily -> Bonus -> Ad)
	user.ConsumeQuery()
	user.LastDraftAt = time.Now()
	database.DB.Model(user).Updates(map[string]interface{}{
		"daily_queries":     user.DailyQueries,
		"bonus_queries":     user.BonusQueries,
		"ad_queries":        user.AdQueries,
		"available_queries": user.AvailableQueries,
		"last_draft_at":     user.LastDraftAt,
	})

	// Send Response
	resp := DraftResponse{Recommendation: recommendation}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
