package middleware

import (
	"backend/internal/auth"
	"backend/internal/config"
	"backend/internal/database"
	"backend/internal/models"
	"context"
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
		sub, jti, err := auth.ValidateJWT(sessionToken)
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

		// Security Check: Verify jti matches to prevent revoked tokens from being used
		if user.SessionToken != jti {
			http.Error(w, "Session expired or logged in from another device", http.StatusUnauthorized)
			return
		}

		// Security Check: Block banned accounts even if they hold a previously issued JWT
		if user.Banned {
			http.Error(w, "Tu cuenta ha sido bloqueada por violar las normas de la comunidad.", http.StatusForbidden)
			return
		}

		ctx := context.WithValue(r.Context(), UserContextKey, &user)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// OptionalAuth adjunta el usuario al contexto si viene un Bearer token válido,
// pero permite continuar como anónimo si no hay token o expiró.
func OptionalAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader != "" && strings.HasPrefix(authHeader, "Bearer ") {
			sessionToken := strings.TrimPrefix(authHeader, "Bearer ")
			if sub, jti, err := auth.ValidateJWT(sessionToken); err == nil {
				var user models.User
				var dbErr error
				if _, errUuid := uuid.Parse(sub); errUuid == nil {
					dbErr = database.DB.Where("id = ?", sub).First(&user).Error
				} else {
					dbErr = database.DB.Where("google_id = ?", sub).First(&user).Error
				}
				if dbErr == nil && user.SessionToken == jti && !user.Banned {
					ctx := context.WithValue(r.Context(), UserContextKey, &user)
					next.ServeHTTP(w, r.WithContext(ctx))
					return
				}
			}
		}
		next.ServeHTTP(w, r)
	})
}
