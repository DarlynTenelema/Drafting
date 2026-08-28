package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"backend/internal/chatcoach"
	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/middleware"
	"backend/internal/models"

	"github.com/google/uuid"
)

type DraftRequest struct {
	ImageBase64   string `json:"image_base64"`
	MainRole      string `json:"main_role"`
	SecondaryRole string `json:"secondary_role"`
	AutofillRole  string `json:"autofill_role"`
	QueryType       string `json:"query_type"`
	OTPChampions    string `json:"otp_champions"`
	ActiveCreatorID string `json:"active_creator_id"`
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
		// Enforce premium-only queries
		if req.QueryType == "otp" || req.QueryType == "in_game" {
			http.Error(w, "Se requiere suscripción Premium para esta función.", http.StatusForbidden)
			return
		}

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

	// Fetch Group Private Rules if user is subscribed to a group
	privateRulesJSON := ""
	if user.ActiveGroupID != nil {
		var group models.Group
		if err := database.DB.First(&group, *user.ActiveGroupID).Error; err == nil {
			privateRulesJSON = group.PrivateJSONData
		}
	}
	
	// Check if active_creator_id is provided and fetch custom rules (Group or CreatorProfile)
	if req.ActiveCreatorID != "" {
		var creatorUserID uuid.UUID
		foundCreator := false

		var profile models.CreatorProfile
		if err := database.DB.Where("id = ?", req.ActiveCreatorID).First(&profile).Error; err == nil {
			creatorUserID = profile.UserID
			foundCreator = true
		} else {
			var group models.Group
			if err := database.DB.Where("id = ?", req.ActiveCreatorID).First(&group).Error; err == nil {
				creatorUserID = group.OwnerID
				foundCreator = true
				if group.PrivateJSONData != "" {
					privateRulesJSON += "\n\nREGLAS DEL GRUPO:\n" + group.PrivateJSONData
				}
			}
		}

		if foundCreator {
			var aiModels []models.AIModel
			if err := database.DB.Where("creator_id = ?", creatorUserID).Find(&aiModels).Error; err == nil && len(aiModels) > 0 {
				customRules, _ := json.Marshal(aiModels)
				privateRulesJSON += "\n\nREGLAS PERSONALIZADAS DEL CREADOR ACTIVO:\n" + string(customRules)
			}
		}
	}

	// Call Gemini API
	recommendation, tokens, err := gemini.AnalyzeDraft(r.Context(), req.ImageBase64, req.MainRole, req.SecondaryRole, req.AutofillRole, privateRulesJSON, req.QueryType, req.OTPChampions)
	if err != nil {
		log.Printf("AnalyzeDraft Error: %v", err)
		http.Error(w, "Ups, el sistema está saturado. No se pudo generar la recomendación. Intenta de nuevo.", http.StatusInternalServerError)
		return
	}

	// Record successful API usage with tokens for cost tracking
	database.DB.Create(&models.ApiUsage{UserID: user.ID, TokensUsed: int(tokens), CreatedAt: time.Now()})

	// Update user's LastDraftAt only if successful
	user.LastDraftAt = time.Now()
	database.DB.Save(user)

	// Trigger Chat Coach processing asynchronously
	go chatcoach.ProcessCapturedImage(user.ID.String(), req.ImageBase64, req.QueryType)

	// Send Response
	resp := DraftResponse{Recommendation: recommendation}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
