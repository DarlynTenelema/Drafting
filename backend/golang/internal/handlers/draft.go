package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
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

	// --- Rate Limiting & Quota Logic ---
	globalFreeTrialEndDateStr := os.Getenv("GLOBAL_FREE_TRIAL_END_DATE")
	if globalFreeTrialEndDateStr == "" {
		globalFreeTrialEndDateStr = "2026-08-16T23:59:59Z"
	}
	globalFreeTrialEndDate, _ := time.Parse(time.RFC3339, globalFreeTrialEndDateStr)

	isPremium := user.SubscriptionEndsAt != nil && user.SubscriptionEndsAt.After(time.Now())

	if !isPremium {
		if time.Now().After(globalFreeTrialEndDate) {
			var count int64
			database.DB.Model(&models.ApiUsage{}).Where("user_id = ?", user.ID).Count(&count)
			
			if count >= 5 {
				http.Error(w, "Prueba gratuita agotada. Límite de 5 peticiones alcanzado.", http.StatusForbidden)
				return
			}
		}
	}
	// -----------------------------------

	// Call Gemini API
	recommendation, err := gemini.AnalyzeDraft(r.Context(), req.ImageBase64, req.MainRole, req.SecondaryRole, req.AutofillRole)
	if err != nil {
		log.Printf("AnalyzeDraft Error: %v", err)
		http.Error(w, "Ups, el sistema está saturado. No se pudo generar la recomendación. Intenta de nuevo.", http.StatusInternalServerError)
		return
	}

	// Record successful API usage
	database.DB.Create(&models.ApiUsage{UserID: user.ID, CreatedAt: time.Now()})

	// Update user's LastDraftAt only if successful
	user.LastDraftAt = time.Now()
	database.DB.Save(user)

	// Send Response
	resp := DraftResponse{Recommendation: recommendation}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
