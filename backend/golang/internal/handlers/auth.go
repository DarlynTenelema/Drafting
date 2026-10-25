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
				GoogleID:         &claims.GoogleID,
				Email:            claims.Email,
				Username:         claims.Name,
				ProfilePic:       claims.Picture,
				SessionToken:     jti,
				AvailableQueries: 10,
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
		// Update existing user with new session jti only. Do NOT overwrite Username and ProfilePic
		// because the user might have customized them via UpdateProfile.
		user.SessionToken = jti
		if err := database.DB.Save(&user).Error; err != nil {
			http.Error(w, "Internal server error: failed to update session: " + err.Error(), http.StatusInternalServerError)
			return
		}
	}

	resp := AuthResponse{SessionToken: tokenStr}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// Me returns the current authenticated user's details and grants daily free queries
func Me(w http.ResponseWriter, r *http.Request) {
	// The Auth middleware already validates the token and attaches the user to the context
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Sistema de 3 consultas gratis cada día (Daily Bonus)
	today := time.Now().UTC().Format("2006-01-02")
	dailyGranted := false
	if user.LastDailyRewardDate != today {
		const dailyBonus = 3
		user.AvailableQueries += dailyBonus
		user.LastDailyRewardDate = today
		database.DB.Model(user).Updates(map[string]interface{}{
			"available_queries":      user.AvailableQueries,
			"last_daily_reward_date": user.LastDailyRewardDate,
		})
		dailyGranted = true
	}

	isPremium := user.SubscriptionEndsAt != nil && user.SubscriptionEndsAt.After(time.Now())
	
	activePlan := "freemium"
	if isPremium && user.ActivePlan != nil {
		activePlan = *user.ActivePlan
	}

	if !isPremium && middleware.IsGlobalFreeTrialActive() {
		isPremium = true
		activePlan = "plus"
	}

	if user.ReferralCode == "" {
		user.ReferralCode = models.GenerateReferralCode(user.ID)
		database.DB.Model(user).Update("referral_code", user.ReferralCode)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":                       user.ID,
		"email":                    user.Email,
		"username":                 user.Username,
		"profile_pic":              user.ProfilePic,
		"role":                     user.Role,
		"is_premium":               isPremium,
		"plan_tier":                activePlan,
		"available_queries":        user.AvailableQueries,
		"daily_reward_granted":     dailyGranted,
		"referral_code":            user.ReferralCode,
		"referral_count":           user.ReferralCount,
		"referral_rewards_claimed": user.ReferralRewardsClaimed,
		"has_redeemed_referral":    user.ReferredByID != nil,
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
	}
	if req.ProfilePic != "" {
		user.ProfilePic = req.ProfilePic
	}

	if err := database.DB.Save(user).Error; err != nil {
		http.Error(w, "Failed to update profile", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":     "Profile updated successfully",
		"username":    user.Username,
		"profile_pic": user.ProfilePic,
	})
}

// ObtainQueries adds reward queries to the user (e.g. from watching an ad or pressing Obtain Queries)
func ObtainQueries(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	const queriesToAdd = 5
	user.AvailableQueries += queriesToAdd

	if err := database.DB.Model(user).Update("available_queries", user.AvailableQueries).Error; err != nil {
		http.Error(w, "Failed to update queries", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"available_queries": user.AvailableQueries,
		"added":             queriesToAdd,
		"message":           "¡Has obtenido 5 consultas!",
	})
}
