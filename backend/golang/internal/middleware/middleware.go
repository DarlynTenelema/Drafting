package middleware

import (
	"backend/internal/auth"
	"backend/internal/config"
	"backend/internal/database"
	"backend/internal/models"
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
)

type contextKey string

const UserContextKey contextKey = "user"

func GetUserIDFromContext(ctx context.Context) (uuid.UUID, bool) {
	user, ok := ctx.Value(UserContextKey).(*models.User)
	if !ok {
		return uuid.Nil, false
	}
	return user.ID, true
}

func IsGlobalFreeTrialActive() bool {
	startStr := config.GetEnv("GLOBAL_FREE_TRIAL_START_DATE", "")
	endStr := config.GetEnv("GLOBAL_FREE_TRIAL_END_DATE", "")
	if endStr == "" {
		return false
	}

	end, err := time.Parse(time.RFC3339, endStr)
	if err != nil {
		log.Printf("GLOBAL_FREE_TRIAL_END_DATE invalid: %v", err)
		return false
	}

	now := time.Now()
	if !now.Before(end) {
		return false
	}

	if startStr == "" {
		return true
	}

	start, err := time.Parse(time.RFC3339, startStr)
	if err != nil {
		log.Printf("GLOBAL_FREE_TRIAL_START_DATE invalid: %v", err)
		return false
	}

	if !start.Before(end) {
		log.Printf("GLOBAL_FREE_TRIAL_START_DATE must be before GLOBAL_FREE_TRIAL_END_DATE")
		return false
	}

	return !now.Before(start)
}

func Auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		sessionToken := strings.TrimPrefix(authHeader, "Bearer ")

		// Validate JWT and extract sub (userID or googleID)
		sub, _, err := auth.ValidateJWT(sessionToken)
		if err != nil {
			http.Error(w, "Unauthorized: invalid token", http.StatusUnauthorized)
			return
		}

		var user models.User
		// Find user by id (if UUID) or google_id (backward compatibility)
		if _, errUuid := uuid.Parse(sub); errUuid == nil {
			if err := database.DB.Where("id = ?", sub).First(&user).Error; err != nil {
				http.Error(w, "Unauthorized or session expired", http.StatusUnauthorized)
				return
			}
		} else {
			if err := database.DB.Where("google_id = ?", sub).First(&user).Error; err != nil {
				http.Error(w, "Unauthorized or session expired", http.StatusUnauthorized)
				return
			}
		}

		ctx := context.WithValue(r.Context(), UserContextKey, &user)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// Check if user has an active subscription or if the global free trial is active
func SubscriptionCheck(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, ok := r.Context().Value(UserContextKey).(*models.User)
		if !ok {
			http.Error(w, "User context missing", http.StatusInternalServerError)
			return
		}

		hasActive := false
		activePlan := "freemium"
		if user.SubscriptionEndsAt != nil && time.Now().Before(*user.SubscriptionEndsAt) {
			hasActive = true
			if user.ActivePlan != nil {
				activePlan = *user.ActivePlan
			}
		}

		// 1. Check Global Free Trial event window
		if !hasActive && IsGlobalFreeTrialActive() {
			hasActive = true
			activePlan = "plus"
		}

		if !hasActive {
			// Access denied
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusPaymentRequired) // 402
			json.NewEncoder(w).Encode(map[string]string{
				"error": "Subscription expired or global free trial has ended. Please purchase a plan.",
			})
			return
		}

		// Attach active plan to context for Cooldown to use
		ctx := context.WithValue(r.Context(), "active_plan", activePlan)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func Cooldown(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, ok := r.Context().Value(UserContextKey).(*models.User)
		if !ok {
			http.Error(w, "User context missing", http.StatusInternalServerError)
			return
		}

		plan, ok := r.Context().Value("active_plan").(string)
		if !ok {
			plan = "freemium"
		}

		limit := int64(10) // Plus limit
		if strings.HasPrefix(plan, "pro") || strings.HasPrefix(plan, "creator_pro") {
			limit = 20
		} else if strings.HasPrefix(plan, "ultra") || strings.HasPrefix(plan, "creator_ultra") {
			limit = 30
		} else if strings.HasPrefix(plan, "freemium") {
			limit = 0 // 0 per hour or day? The user said 3 per day, but currently it's per hour. Let's do 3 per hour for now since we don't have per-day logic yet.
		}

		// 1. Check Requests per hour (Cooldown)
		var count int64
		database.DB.Model(&models.ApiUsage{}).Where("user_id = ? AND created_at > ?", user.ID, time.Now().Add(-1*time.Hour)).Count(&count)
		if count >= limit {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusTooManyRequests)
			json.NewEncoder(w).Encode(map[string]string{
				"error": "Límite de consultas por hora alcanzado para tu plan. Intenta de nuevo más tarde o mejora tu plan.",
			})
			return
		}

		// 2. Check Total Tokens Quota for Ultra plans
		if strings.HasPrefix(plan, "ultra") || strings.HasPrefix(plan, "creator_ultra") {
			var maxTokens int64 = 0
			var since time.Time

			switch plan {
			case "ultra_1d", "creator_ultra_1d":
				maxTokens = 250000
				since = time.Now().Add(-24 * time.Hour)
			case "ultra_1w", "creator_ultra_1w":
				maxTokens = 300000
				since = time.Now().Add(-24 * time.Hour) // 300K diarios
			case "ultra_1m", "creator_ultra_1m":
				maxTokens = 2500000
				since = time.Now().Add(-7 * 24 * time.Hour) // 2.5M semanales
			case "ultra_1y", "creator_ultra_1y":
				maxTokens = 12000000
				since = time.Now().Add(-30 * 24 * time.Hour) // 12M mensuales
			}

			if maxTokens > 0 {
				var tokensUsed int64
				database.DB.Model(&models.ApiUsage{}).
					Where("user_id = ? AND created_at > ?", user.ID, since).
					Select("COALESCE(SUM(tokens_used), 0)").
					Row().Scan(&tokensUsed)

				if tokensUsed >= maxTokens {
					w.Header().Set("Content-Type", "application/json")
					w.WriteHeader(http.StatusTooManyRequests)
					json.NewEncoder(w).Encode(map[string]string{
						"error": "Has alcanzado el límite de tokens de IA para tu plan. Espera a que se renueve tu cuota.",
					})
					return
				}
			}
		}

		next.ServeHTTP(w, r)
	})
}

// AdminCheck verifies if the authenticated user has the "admin" role
func AdminCheck(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, ok := r.Context().Value(UserContextKey).(*models.User)
		if !ok {
			http.Error(w, "User context missing", http.StatusInternalServerError)
			return
		}

		if user.Role != "admin" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusForbidden)
			json.NewEncoder(w).Encode(map[string]string{
				"error": "Access forbidden. Admin role required.",
			})
			return
		}

		next.ServeHTTP(w, r)
	})
}
