package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"backend/internal/auth"
	"backend/internal/database"
	"backend/internal/models"
	"gorm.io/gorm"
)

type AuthRequest struct {
	GoogleToken string `json:"google_token"`
}

type AuthResponse struct {
	SessionToken string `json:"session_token"`
}

func GoogleLogin(w http.ResponseWriter, r *http.Request) {
	var req AuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	claims, err := auth.VerifyGoogleToken(r.Context(), req.GoogleToken)
	if err != nil {
		http.Error(w, "Invalid Google token", http.StatusUnauthorized)
		return
	}

	var user models.User
	result := database.DB.Where("google_id = ?", claims.GoogleID).First(&user)

	// Generate a JWT (365 days TTL)
	tokenStr, jti, err := auth.GenerateJWT(claims.GoogleID, 365*24*time.Hour)
	if err != nil {
		http.Error(w, "Internal server error: failed to generate token", http.StatusInternalServerError)
		return
	}

	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			// User does not exist, create new.
			user = models.User{
				GoogleID:     &claims.GoogleID,
				Email:        claims.Email,
				SessionToken: jti,
			}
			if err := database.DB.Create(&user).Error; err != nil {
				http.Error(w, "Internal server error: failed to create user", http.StatusInternalServerError)
				return
			}
		} else {
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}
	} else {
		// Update existing user with new session jti (revokes previous sessions)
		user.SessionToken = jti
		if err := database.DB.Save(&user).Error; err != nil {
			http.Error(w, "Internal server error: failed to update session", http.StatusInternalServerError)
			return
		}
	}

	resp := AuthResponse{SessionToken: tokenStr}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
