package handlers

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"strings"
	"time"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"

	"gorm.io/gorm/clause"
)

type DonationTier struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	PriceUSD     float64 `json:"price_usd"`
	BonusQueries int     `json:"bonus_queries"`
	Badge        string  `json:"badge"`
	IconType     string  `json:"icon_type"`
}

var AvailableDonationTiers = []DonationTier{
	{
		ID:           "donate_10",
		Name:         "Chispa Hextech",
		PriceUSD:     0.10,
		BonusQueries: 2,
		Badge:        "Aporte Inicial",
		IconType:     "spark",
	},
	{
		ID:           "donate_25",
		Name:         "Moneda Hextech",
		PriceUSD:     0.25,
		BonusQueries: 5,
		Badge:        "Popular",
		IconType:     "coin",
	},
	{
		ID:           "donate_49",
		Name:         "Cristal de Apoyo",
		PriceUSD:     0.49,
		BonusQueries: 10,
		Badge:        "Impulso Streamer",
		IconType:     "crystal",
	},
	{
		ID:           "donate_75",
		Name:         "Orbe Challenger",
		PriceUSD:     0.75,
		BonusQueries: 15,
		Badge:        "Destacado",
		IconType:     "orb",
	},
	{
		ID:           "donate_99",
		Name:         "Corona Leyenda",
		PriceUSD:     0.99,
		BonusQueries: 25,
		Badge:        "Top Ranking",
		IconType:     "crown",
	},
}

func ResolveDonationTier(id string) (DonationTier, bool) {
	clean := strings.TrimSpace(strings.ToLower(id))
	for _, t := range AvailableDonationTiers {
		if t.ID == clean {
			return t, true
		}
	}
	return DonationTier{}, false
}

// GetDonationsRanking devuelve los niveles de micro-donación, el ranking de donadores y el perfil del usuario actual
func GetDonationsRanking(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	user, _ := r.Context().Value(middleware.UserContextKey).(*models.User)

	var donors []models.DonorProfile
	if db != nil {
		db.Where("total_donated_usd > 0").
			Order("total_donated_usd DESC, is_live DESC, last_donated_at DESC").
			Limit(50).
			Find(&donors)
	}

	rankingList := make([]map[string]interface{}, 0, len(donors))
	for idx, d := range donors {
		rankingList = append(rankingList, map[string]interface{}{
			"rank":              idx + 1,
			"id":                d.ID,
			"user_id":           d.UserID,
			"display_name":      d.DisplayName,
			"avatar_url":        d.AvatarURL,
			"platform":          d.Platform,
			"channel_handle":    d.ChannelHandle,
			"channel_url":       d.ChannelURL,
			"bio_message":       d.BioMessage,
			"is_live":           d.IsLive,
			"total_donated_usd": d.TotalDonatedUSD,
			"donations_count":   d.DonationsCount,
			"last_donated_at":   d.LastDonatedAt,
		})
	}

	var myProfile *models.DonorProfile
	if user != nil && db != nil {
		var found []models.DonorProfile
		if err := db.Where("user_id = ?", user.ID).Limit(1).Find(&found).Error; err == nil && len(found) > 0 {
			myProfile = &found[0]
		}
	}

	canEditProfile := false
	if user != nil {
		if myProfile != nil && myProfile.TotalDonatedUSD > 0 {
			canEditProfile = true
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"tiers":            AvailableDonationTiers,
		"ranking":          rankingList,
		"my_donor_profile": myProfile,
		"can_edit_profile": canEditProfile,
	})
}

type ContributeDonationRequest struct {
	TierID                string `json:"tier_id"`
	ProviderTransactionID string `json:"provider_transaction_id"`
	Provider              string `json:"provider"`
	PurchaseToken         string `json:"purchase_token,omitempty"`
}

// ContributeDonation acredita una micro-donación de Google Play Billing y actualiza la posición del usuario en el Ranking
func ContributeDonation(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req ContributeDonationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Solicitud inválida", http.StatusBadRequest)
		return
	}

	tier, exists := ResolveDonationTier(req.TierID)
	if !exists {
		http.Error(w, "Nivel de donación no válido.", http.StatusBadRequest)
		return
	}

	provider, txID, purchaseToken, errMsg := ValidateStoreReceipt(req.Provider, req.ProviderTransactionID, req.PurchaseToken)
	if errMsg != "" {
		http.Error(w, errMsg, http.StatusBadRequest)
		return
	}

	tx := database.DB.Begin()
	if tx.Error != nil {
		http.Error(w, "Error iniciando transacción", http.StatusInternalServerError)
		return
	}

	var lockedUser models.User
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", user.ID).First(&lockedUser).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Usuario no encontrado", http.StatusNotFound)
		return
	}

	// Idempotencia estricta
	var existing models.Transaction
	idempotencyQuery := tx.Where("status = 'completed' AND provider_transaction_id = ?", txID)
	if purchaseToken != "" {
		idempotencyQuery = tx.Where(
			"status = 'completed' AND (provider_transaction_id = ? OR provider_transaction_id = ? OR (purchase_token != '' AND purchase_token = ?))",
			txID, purchaseToken, purchaseToken,
		)
	}
	if err := idempotencyQuery.First(&existing).Error; err == nil {
		tx.Rollback()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success":           true,
			"already_processed": true,
			"message":           "Donación ya registrada anteriormente.",
			"queries_added":     0,
			"available_queries": lockedUser.AvailableQueries,
		})
		return
	}

	// Acreditar consultas de agradecimiento
	lockedUser.RecalculateAvailableQueries()
	lockedUser.AddPurchasedQueries(tier.BonusQueries)

	txRecord := models.Transaction{
		UserID:                lockedUser.ID,
		Type:                  "donation",
		ItemKey:               tier.ID,
		AmountUSD:             tier.PriceUSD,
		QueriesAdded:          tier.BonusQueries,
		Provider:              provider,
		ProviderTransactionID: txID,
		PurchaseToken:         purchaseToken,
		Status:                "completed",
		CreatedAt:             time.Now().UTC(),
	}
	if err := tx.Create(&txRecord).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Error registrando donación", http.StatusInternalServerError)
		return
	}

	if err := tx.Model(&lockedUser).Updates(map[string]interface{}{
		"purchased_queries": lockedUser.PurchasedQueries,
		"available_queries": lockedUser.AvailableQueries,
	}).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Error actualizando usuario", http.StatusInternalServerError)
		return
	}

	// Crear o actualizar perfil en el Ranking de Donadores
	var donor models.DonorProfile
	now := time.Now().UTC()
	if err := tx.Where("user_id = ?", lockedUser.ID).First(&donor).Error; err != nil {
		displayName := strings.TrimSpace(lockedUser.Username)
		if displayName == "" {
			displayName = lockedUser.ReferralCode
		}
		donor = models.DonorProfile{
			UserID:          lockedUser.ID,
			DisplayName:     displayName,
			AvatarURL:       lockedUser.ProfilePic,
			Platform:        "tiktok",
			TotalDonatedUSD: tier.PriceUSD,
			DonationsCount:  1,
			LastDonatedAt:   now,
			CreatedAt:       now,
			UpdatedAt:       now,
		}
		tx.Create(&donor)
	} else {
		donor.TotalDonatedUSD = math.Round((donor.TotalDonatedUSD+tier.PriceUSD)*100) / 100
		donor.DonationsCount += 1
		donor.LastDonatedAt = now
		donor.UpdatedAt = now
		if donor.AvatarURL == "" && lockedUser.ProfilePic != "" {
			donor.AvatarURL = lockedUser.ProfilePic
		}
		tx.Save(&donor)
	}

	if err := tx.Commit().Error; err != nil {
		http.Error(w, "Error confirmando donación", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":           true,
		"already_processed": false,
		"message":           fmt.Sprintf("¡Gracias por tu aporte de $%.2f! Subiste en el Ranking de Donadores y recibiste +%d consultas de regalo.", tier.PriceUSD, tier.BonusQueries),
		"tier_id":           tier.ID,
		"queries_added":     tier.BonusQueries,
		"available_queries": lockedUser.AvailableQueries,
		"donor_profile":     donor,
	})
}

type UpdateDonorProfileRequest struct {
	DisplayName   string `json:"display_name"`
	Platform      string `json:"platform"` // "tiktok" | "twitch" | "kick"
	ChannelHandle string `json:"channel_handle"`
	ChannelURL    string `json:"channel_url"`
	BioMessage    string `json:"bio_message"`
	IsLive        bool   `json:"is_live"`
}

// normalizeStreamURL limpia y garantiza que el enlace apunte a Twitch, Kick o TikTok
func normalizeStreamURL(platform, rawURL, handle string) string {
	url := strings.TrimSpace(rawURL)
	cleanHandle := strings.TrimPrefix(strings.TrimSpace(handle), "@")

	if url == "" && cleanHandle != "" {
		switch platform {
		case "twitch":
			return "https://www.twitch.tv/" + cleanHandle
		case "kick":
			return "https://kick.com/" + cleanHandle
		default:
			return "https://www.tiktok.com/@" + cleanHandle
		}
	}
	if url != "" && !strings.HasPrefix(strings.ToLower(url), "http://") && !strings.HasPrefix(strings.ToLower(url), "https://") {
		url = "https://" + url
	}
	return url
}

// UpdateDonorProfile permite al donador configurar su canal de Twitch, Kick o TikTok y activar su estado En Directo
func UpdateDonorProfile(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req UpdateDonorProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Solicitud inválida", http.StatusBadRequest)
		return
	}

	db := database.GetDB()
	var donor models.DonorProfile
	err := db.Where("user_id = ?", user.ID).First(&donor).Error

	if err != nil {
		http.Error(w, "Realiza tu primer aporte (desde $0.10) para desbloquear tu perfil en el Ranking y compartir tu canal.", http.StatusForbidden)
		return
	}

	platform := strings.ToLower(strings.TrimSpace(req.Platform))
	if platform != "twitch" && platform != "kick" && platform != "tiktok" {
		platform = "tiktok"
	}

	displayName := strings.TrimSpace(req.DisplayName)
	if displayName == "" {
		displayName = user.Username
		if displayName == "" {
			displayName = user.ReferralCode
		}
	}

	handle := strings.TrimSpace(req.ChannelHandle)
	if handle != "" && !strings.HasPrefix(handle, "@") && platform == "tiktok" {
		handle = "@" + handle
	}

	channelURL := normalizeStreamURL(platform, req.ChannelURL, handle)
	if channelURL == "" {
		http.Error(w, "Ingresa el usuario o enlace de tu canal de Twitch, Kick o TikTok.", http.StatusBadRequest)
		return
	}

	donor.DisplayName = displayName
	donor.Platform = platform
	donor.ChannelHandle = handle
	donor.ChannelURL = channelURL
	donor.BioMessage = strings.TrimSpace(req.BioMessage)
	donor.IsLive = req.IsLive
	if user.ProfilePic != "" {
		donor.AvatarURL = user.ProfilePic
	}
	donor.UpdatedAt = time.Now().UTC()

	if err != nil {
		db.Create(&donor)
	} else {
		db.Save(&donor)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":       true,
		"message":       "¡Tu canal y estado de directo se han actualizado en el Ranking de Donadores!",
		"donor_profile": donor,
	})
}

