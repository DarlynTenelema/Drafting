package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"backend/internal/auth"
	"backend/internal/database"
	"backend/internal/middleware"
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

// Me returns the current authenticated user's details
func Me(w http.ResponseWriter, r *http.Request) {
	// The Auth middleware already validates the token and attaches the user to the context
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	isPremium := user.SubscriptionEndsAt != nil && user.SubscriptionEndsAt.After(time.Now())

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id": user.ID,
		"email": user.Email,
		"username": user.Username,
		"profile_pic": user.ProfilePic,
		"role": user.Role,
		"is_pending_ban": user.IsPendingBan,
		"banned": user.Banned,
		"strikes": user.Strikes,
		"is_premium": isPremium,
	})
}

type UpdateProfileRequest struct {
	Username   string `json:"username"`
	ProfilePic string `json:"profile_pic"`
}

// UpdateProfile allows a user to update their username and profile pic
func UpdateProfile(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req UpdateProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.Username != "" {
		user.Username = req.Username
		// Sync with Channel and CreatorProfile
		database.DB.Model(&models.Channel{}).Where("owner_id = ?", user.ID).Update("name", req.Username)
		database.DB.Model(&models.CreatorProfile{}).Where("user_id = ?", user.ID).Update("artist_name", req.Username)
	}
	if req.ProfilePic != "" {
		user.ProfilePic = req.ProfilePic
		// Sync with Channel logo
		database.DB.Model(&models.Channel{}).Where("owner_id = ?", user.ID).Update("logo_url", req.ProfilePic)
	}

	if err := database.DB.Save(user).Error; err != nil {
		http.Error(w, "Failed to update profile", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message": "Profile updated successfully",
		"username": user.Username,
		"profile_pic": user.ProfilePic,
	})
}


