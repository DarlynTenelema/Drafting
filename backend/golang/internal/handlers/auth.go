package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"backend/internal/auth"
	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
	"gorm.io/gorm"
)

type AuthRequest struct {
	GoogleToken string `json:"google_token"`
	DeviceID    string `json:"device_id"`
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

	if req.DeviceID != "" {
		var bannedUsers []models.User
		if err := database.DB.Where("device_id = ? AND banned = ?", req.DeviceID, true).Limit(1).Find(&bannedUsers).Error; err == nil && len(bannedUsers) > 0 {
			http.Error(w, "Este dispositivo ha sido bloqueado por violar las normas de la comunidad.", http.StatusForbidden)
			return
		}
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
			// User does not exist, create new with Classic daily cap (3)
			now := time.Now().UTC()
			user = models.User{
				GoogleID:              &claims.GoogleID,
				Email:                 claims.Email,
				Username:              claims.Name,
				ProfilePic:            claims.Picture,
				DeviceID:              req.DeviceID,
				SessionToken:          jti,
				ClassicDaily:          models.ClassicDailyCap,
				ClassicLastRechargeAt: &now,
				DailyQueries:          models.ClassicDailyCap,
				BonusQueries:          0,
				AdQueries:             0,
				AvailableQueries:      models.ClassicDailyCap,
				LastDailyRewardDate:   now.Format("2006-01-02"),
				ModelsV2Migrated:      true,
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
		// Update existing user with new session jti.
		user.SessionToken = jti
		if req.DeviceID != "" && user.DeviceID == "" {
			user.DeviceID = req.DeviceID
		}
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

	// Sistema de consultas diarias Classic (tope máximo 3 cada 24h) y reinicio de límites AdMob para Flake/Aureon
	now := time.Now().UTC()
	today := now.Format("2006-01-02")
	prevAvailable := user.AvailableQueries
	dailyGranted := user.RefreshClassicDaily(now)
	adsReset := user.ResetModelAdLimitsIfNewDay(today)
	user.ResetDailyLimitsIfNewDay(today)
	user.SyncModelWalletsToTotals()

	if dailyGranted || adsReset || user.AvailableQueries != prevAvailable {
		database.DB.Model(user).Updates(map[string]interface{}{
			"classic_daily":            user.ClassicDaily,
			"classic_last_recharge_at": user.ClassicLastRechargeAt,
			"daily_queries":            user.DailyQueries,
			"ad_queries":               user.AdQueries,
			"purchased_queries":        user.PurchasedQueries,
			"available_queries":        user.AvailableQueries,
			"last_daily_reward_date":   user.LastDailyRewardDate,
			"flake_ads_today":          user.FlakeAdsToday,
			"flake_last_ad_date":       user.FlakeLastAdDate,
			"aureon_ads_today":         user.AureonAdsToday,
			"aureon_last_ad_date":      user.AureonLastAdDate,
		})
	}

	isPremium := false
	activePlan := "freemium"

	if user.ReferralCode == "" {
		user.ReferralCode = models.GenerateReferralCode(user.ID)
		database.DB.Model(user).Update("referral_code", user.ReferralCode)
	}

	remainingTransfer := 10 - user.DailyTransferredToday
	if remainingTransfer < 0 {
		remainingTransfer = 0
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":                       user.ID,
		"email":                    user.Email,
		"username":                 user.Username,
		"profile_pic":              user.ProfilePic,
		"bio":                      user.Bio,
		"twitch_url":               user.TwitchURL,
		"tiktok_url":               user.TikTokURL,
		"youtube_url":              user.YouTubeURL,
		"instagram_url":            user.InstagramURL,
		"kick_url":                 user.KickURL,
		"lifetime_verified_views":  user.LifetimeVerifiedViews,
		"role":                     user.Role,
		"is_premium":               isPremium,
		"plan_tier":                activePlan,
		"available_queries":        user.AvailableQueries,
		"daily_queries":            user.DailyQueries,
		"bonus_queries":            user.BonusQueries,
		"ad_queries":               user.AdQueries,
		"purchased_queries":        user.PurchasedQueries,
		"subscription_queries":     user.SubscriptionQueries,
		"gift_queries":             user.GiftQueries,
		"classic_queries":          user.ClassicQueries(),
		"classic_daily":            user.ClassicDaily,
		"classic_ad":               user.ClassicAd,
		"classic_purchased":        user.ClassicPurchased,
		"flake_queries":            user.FlakeQueries(),
		"flake_ad":                 user.FlakeAd,
		"flake_purchased":          user.FlakePurchased,
		"flake_ads_today":          user.FlakeAdsToday,
		"flake_ads_remaining":      user.RemainingAdsForModel(models.ModelFlake, today),
		"aureon_queries":           user.AureonQueries(),
		"aureon_ad":                user.AureonAd,
		"aureon_purchased":         user.AureonPurchased,
		"aureon_ads_today":         user.AureonAdsToday,
		"aureon_ads_remaining":     user.RemainingAdsForModel(models.ModelAureon, today),
		"subscription_plan":        "none",
		"has_purchased_starter":    user.HasPurchasedStarter,
		"daily_transferred_today":  user.DailyTransferredToday,
		"remaining_transfer_today": remainingTransfer,
		"can_transfer":             user.CanTransfer() && remainingTransfer > 0,
		"daily_reward_granted":     dailyGranted,
		"referral_code":            user.ReferralCode,
		"referral_count":           user.ReferralCount,
		"referral_rewards_claimed": user.ReferralRewardsClaimed,
		"has_redeemed_referral":    user.ReferredByID != nil,
		"app_version":              GetCurrentAppVersionInfo(),
	})
}

type UpdateProfileRequest struct {
	Username     *string `json:"username,omitempty"`
	ProfilePic   *string `json:"profile_pic,omitempty"`
	Bio          *string `json:"bio,omitempty"`
	TwitchURL    *string `json:"twitch_url,omitempty"`
	TikTokURL    *string `json:"tiktok_url,omitempty"`
	YouTubeURL   *string `json:"youtube_url,omitempty"`
	InstagramURL *string `json:"instagram_url,omitempty"`
	KickURL      *string `json:"kick_url,omitempty"`
}

func validateSocialURL(raw string, allowedHosts []string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", nil
	}
	if !strings.HasPrefix(strings.ToLower(trimmed), "http://") && !strings.HasPrefix(strings.ToLower(trimmed), "https://") {
		trimmed = "https://" + trimmed
	}
	parsed, err := url.Parse(trimmed)
	if err != nil || parsed.Host == "" {
		return "", errors.New("URL inválida")
	}
	if strings.ToLower(parsed.Scheme) != "https" {
		parsed.Scheme = "https"
	}
	host := strings.ToLower(parsed.Hostname())
	allowed := false
	for _, h := range allowedHosts {
		if host == h || strings.HasSuffix(host, "."+h) {
			allowed = true
			break
		}
	}
	if !allowed {
		return "", errors.New("dominio no permitido para esta red social")
	}
	finalURL := parsed.String()
	if len(finalURL) > 255 {
		return "", errors.New("la URL es demasiado larga (máximo 255 caracteres)")
	}
	return finalURL, nil
}

// UpdateProfile allows a user to update their username, profile pic, bio and creator social links
func UpdateProfile(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var req UpdateProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.Username != nil {
		cleanName := strings.TrimSpace(*req.Username)
		if cleanName != "" {
			if len(cleanName) > 60 {
				cleanName = cleanName[:60]
			}
			user.Username = cleanName
		}
	}
	if req.ProfilePic != nil {
		cleanPic := strings.TrimSpace(*req.ProfilePic)
		if cleanPic != "" {
			user.ProfilePic = cleanPic
		}
	}
	if req.Bio != nil {
		cleanBio := strings.TrimSpace(*req.Bio)
		if len([]rune(cleanBio)) > 220 {
			cleanBio = string([]rune(cleanBio)[:220])
		}
		user.Bio = cleanBio
	}

	if req.TwitchURL != nil {
		u, err := validateSocialURL(*req.TwitchURL, []string{"twitch.tv"})
		if err != nil {
			http.Error(w, `{"error":"Link de Twitch inválido (debe ser de twitch.tv)"}`, http.StatusBadRequest)
			return
		}
		user.TwitchURL = u
	}
	if req.TikTokURL != nil {
		u, err := validateSocialURL(*req.TikTokURL, []string{"tiktok.com"})
		if err != nil {
			http.Error(w, `{"error":"Link de TikTok inválido (debe ser de tiktok.com)"}`, http.StatusBadRequest)
			return
		}
		user.TikTokURL = u
	}
	if req.YouTubeURL != nil {
		u, err := validateSocialURL(*req.YouTubeURL, []string{"youtube.com", "youtu.be"})
		if err != nil {
			http.Error(w, `{"error":"Link de YouTube inválido (debe ser de youtube.com o youtu.be)"}`, http.StatusBadRequest)
			return
		}
		user.YouTubeURL = u
	}
	if req.InstagramURL != nil {
		u, err := validateSocialURL(*req.InstagramURL, []string{"instagram.com"})
		if err != nil {
			http.Error(w, `{"error":"Link de Instagram inválido (debe ser de instagram.com)"}`, http.StatusBadRequest)
			return
		}
		user.InstagramURL = u
	}
	if req.KickURL != nil {
		u, err := validateSocialURL(*req.KickURL, []string{"kick.com"})
		if err != nil {
			http.Error(w, `{"error":"Link de Kick inválido (debe ser de kick.com)"}`, http.StatusBadRequest)
			return
		}
		user.KickURL = u
	}

	if err := database.DB.Save(user).Error; err != nil {
		http.Error(w, `{"error":"Failed to update profile"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":       "Profile updated successfully",
		"username":      user.Username,
		"profile_pic":   user.ProfilePic,
		"bio":           user.Bio,
		"twitch_url":    user.TwitchURL,
		"tiktok_url":    user.TikTokURL,
		"youtube_url":   user.YouTubeURL,
		"instagram_url": user.InstagramURL,
		"kick_url":      user.KickURL,
	})
}

var lastObtainQueryMap sync.Map // map[uuid.UUID]time.Time

type ObtainQueriesRequest struct {
	ModelTier string `json:"model_tier,omitempty"` // "classic", "flake", "aureon"
}

// ObtainQueries otorga recompensas por ver un anuncio de Google AdMob según el modelo:
// - Classic: +2 consultas
// - Flake 1.0: +1 consulta (máximo 2 veces al día, luego entra en enfriamiento)
// - Aureon 1.0: +1 consulta (máximo 1 vez al día, luego entra en enfriamiento)
func ObtainQueries(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req ObtainQueriesRequest
	_ = json.NewDecoder(r.Body).Decode(&req)
	modelTier := models.NormalizeModelTier(req.ModelTier)

	// Antifraude: Cooldown de 15 segundos entre recargas de consultas
	if lastTime, exists := lastObtainQueryMap.Load(user.ID); exists {
		if t, ok := lastTime.(time.Time); ok && time.Since(t) < 15*time.Second {
			http.Error(w, "Por favor espera 15 segundos antes de solicitar otra recarga.", http.StatusTooManyRequests)
			return
		}
	}

	today := time.Now().UTC().Format("2006-01-02")
	added, granted := user.GrantAdRewardForModel(modelTier, today)
	if !granted {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusTooManyRequests)
		msg := "Has alcanzado el límite diario de anuncios para este modelo. Vuelve mañana o adquiere un paquete."
		if modelTier == models.ModelFlake {
			msg = "Flake 1.0 en enfriamiento (máximo 2 anuncios por día). Vuelve mañana."
		} else if modelTier == models.ModelAureon {
			msg = "Aureon 1.0 en enfriamiento (máximo 1 anuncio por día). Vuelve mañana."
		}
		json.NewEncoder(w).Encode(map[string]interface{}{
			"cooldown":             true,
			"model_tier":           modelTier,
			"message":              msg,
			"flake_ads_remaining":  user.RemainingAdsForModel(models.ModelFlake, today),
			"aureon_ads_remaining": user.RemainingAdsForModel(models.ModelAureon, today),
		})
		return
	}

	lastObtainQueryMap.Store(user.ID, time.Now())

	if err := database.DB.Model(user).Updates(map[string]interface{}{
		"classic_ad":          user.ClassicAd,
		"flake_ad":            user.FlakeAd,
		"flake_ads_today":     user.FlakeAdsToday,
		"flake_last_ad_date":  user.FlakeLastAdDate,
		"aureon_ad":           user.AureonAd,
		"aureon_ads_today":    user.AureonAdsToday,
		"aureon_last_ad_date": user.AureonLastAdDate,
		"ad_queries":          user.AdQueries,
		"available_queries":   user.AvailableQueries,
	}).Error; err != nil {
		http.Error(w, "Failed to update queries", http.StatusInternalServerError)
		return
	}

	modelLabel := "Classic"
	if modelTier == models.ModelFlake {
		modelLabel = "Flake 1.0"
	} else if modelTier == models.ModelAureon {
		modelLabel = "Aureon 1.0"
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"model_tier":           modelTier,
		"available_queries":    user.AvailableQueries,
		"classic_queries":      user.ClassicQueries(),
		"flake_queries":        user.FlakeQueries(),
		"aureon_queries":       user.AureonQueries(),
		"flake_ads_remaining":  user.RemainingAdsForModel(models.ModelFlake, today),
		"aureon_ads_remaining": user.RemainingAdsForModel(models.ModelAureon, today),
		"daily_queries":        user.DailyQueries,
		"bonus_queries":        user.BonusQueries,
		"ad_queries":           user.AdQueries,
		"added":                added,
		"message":              "¡Has obtenido +" + string(rune('0'+added)) + " consulta(s) de " + modelLabel + "!",
	})
}
