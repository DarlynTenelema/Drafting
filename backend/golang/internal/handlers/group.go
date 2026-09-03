package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/google/uuid"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
)

type SaveChampionDataRequest struct {
	ChampionName string `json:"champion_name"`
	Rules        string `json:"rules"` // Text rules written by entrepreneur
}

// SaveChampionData allows entrepreneurs and creators to save their private JSON for a champion.
func SaveChampionData(w http.ResponseWriter, r *http.Request) {
	var req SaveChampionDataRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || (user.Role != "entrepreneur" && user.Role != "creator") {
		http.Error(w, "Unauthorized. Only entrepreneurs and creators can save champion data.", http.StatusUnauthorized)
		return
	}

	// Fetch the entrepreneur's group
	var group models.Group
	if err := database.DB.Where("owner_id = ?", user.ID).First(&group).Error; err != nil {
		// If group not found, save directly to AIModel for OTP creators
		aiModel := models.AIModel{
			CreatorID:         user.ID,
			ChampionName:      req.ChampionName,
			EarlyGameStrategy: req.Rules,
		}
		var existing models.AIModel
		if errM := database.DB.Where("creator_id = ? AND champion_name = ?", user.ID, req.ChampionName).First(&existing).Error; errM == nil {
			existing.EarlyGameStrategy = req.Rules
			database.DB.Save(&existing)
		} else {
			database.DB.Create(&aiModel)
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]bool{"success": true})
		return
	}

	// Parse existing JSON
	championData := make(map[string]string)
	if group.PrivateJSONData != "" {
		if err := json.Unmarshal([]byte(group.PrivateJSONData), &championData); err != nil {
			http.Error(w, "Failed to parse existing rules", http.StatusInternalServerError)
			return
		}
	}

	// Update specific champion rules
	championData[req.ChampionName] = req.Rules

	// Save back to group
	updatedJSON, err := json.Marshal(championData)
	if err != nil {
		http.Error(w, "Failed to encode rules", http.StatusInternalServerError)
		return
	}
	group.PrivateJSONData = string(updatedJSON)

	if err := database.DB.Save(&group).Error; err != nil {
		http.Error(w, "Failed to save group data", http.StatusInternalServerError)
		return
	}

	// Also sync to AIModel
	var existing models.AIModel
	if errM := database.DB.Where("creator_id = ? AND champion_name = ?", user.ID, req.ChampionName).First(&existing).Error; errM == nil {
		existing.EarlyGameStrategy = req.Rules
		database.DB.Save(&existing)
	} else {
		database.DB.Create(&models.AIModel{
			CreatorID:         user.ID,
			ChampionName:      req.ChampionName,
			EarlyGameStrategy: req.Rules,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}

func GetMyChampions(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	championSet := make(map[string]bool)

	var group models.Group
	if err := database.DB.Where("owner_id = ?", user.ID).First(&group).Error; err == nil && group.PrivateJSONData != "" {
		var championData map[string]string
		if err := json.Unmarshal([]byte(group.PrivateJSONData), &championData); err == nil {
			for k := range championData {
				championSet[k] = true
			}
		}
	}

	// Also check AIModel table
	var aiModels []models.AIModel
	if err := database.DB.Where("creator_id = ?", user.ID).Find(&aiModels).Error; err == nil {
		for _, m := range aiModels {
			championSet[m.ChampionName] = true
		}
	}

	// Also check CreatorProfile
	var profile models.CreatorProfile
	if err := database.DB.Where("user_id = ?", user.ID).First(&profile).Error; err == nil {
		if profile.ArtistName != "" {
			championSet[profile.ArtistName] = true
		}
	}

	// Also check OTPProfile
	var otp models.OTPProfile
	if err := database.DB.Where("owner_id = ?", user.ID).First(&otp).Error; err == nil {
		if otp.ChampionName != "" {
			championSet[otp.ChampionName] = true
		}
	}

	var championsList []string
	for k := range championSet {
		championsList = append(championsList, k)
	}

	if len(championsList) == 0 {
		championsList = []string{"Ahri"}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(championsList)
}


type CreateGroupRequest struct {
	Name             string   `json:"name"`
	Description      string   `json:"description"`
	SubscriptionPlan string   `json:"subscription_plan"` // E.g., "100", "300", "500"
	ProductName      string   `json:"product_name"`
	ProductImage     string   `json:"product_image"`
	PurchaseToken    string   `json:"purchase_token"`
	Invites          []string `json:"invites"`           // Emails to invite
}

// helper to check if user is eligible internally
func checkUserEligibility(user *models.User) bool {
	return !user.HasUsedCreatorTrial
}

func CreateGroup(w http.ResponseWriter, r *http.Request) {
	var req CreateGroupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// 1. Validate Invites based on Plan
	requiredInvites := 5
	if req.SubscriptionPlan == "300" || req.SubscriptionPlan == "300.0" || req.SubscriptionPlan == "300.00" {
		requiredInvites = 15
	} else if req.SubscriptionPlan == "500" || req.SubscriptionPlan == "500.0" || req.SubscriptionPlan == "500.00" {
		requiredInvites = 20
	}

	if len(req.Invites) < requiredInvites {
		http.Error(w, "Not enough members invited for the selected plan", http.StatusBadRequest)
		return
	}

	// 2. Validate Payment
	isEligible := checkUserEligibility(user)
	if !isEligible {
		if req.PurchaseToken == "" {
			http.Error(w, "Payment required. Free trial already used.", http.StatusPaymentRequired)
			return
		}
		if playStoreVerifier != nil && playStoreVerifier.Enabled() {
			if err := playStoreVerifier.VerifySubscriptionPurchase(r.Context(), req.PurchaseToken); err != nil {
				http.Error(w, "Payment verification failed: "+err.Error(), http.StatusPaymentRequired)
				return
			}
		}
	}

	group := models.Group{
		OwnerID:          user.ID,
		Name:             req.Name,
		Description:      req.Description,
		SubscriptionPlan: req.SubscriptionPlan,
		ProductName:      req.ProductName,
		ProductImage:     req.ProductImage,
		PrivateJSONData:  "{}",
		IsActive:         true, // Active immediately for Free Month
	}

	if err := database.DB.Create(&group).Error; err != nil {
		http.Error(w, "Failed to create group", http.StatusInternalServerError)
		return
	}

	if len(req.Invites) > 0 {
		for _, email := range req.Invites {
			invite := models.GroupInvitation{
				GroupID: group.ID,
				Email:   email,
				Status:  "pending",
			}
			database.DB.Create(&invite)
		}
	}

	if user.Role != "entrepreneur" {
		user.Role = "entrepreneur"
	}
	
	if isEligible && req.PurchaseToken == "" {
		user.HasUsedCreatorTrial = true
	}
	database.DB.Save(user)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(group)
}

type CreateOTPProfileRequest struct {
	ChampionName     string `json:"champion_name"`
	Description      string `json:"description"`
	SubscriptionPlan string `json:"subscription_plan"` // E.g., "10", "30", "50"
	ProductName      string `json:"product_name"`
	ProductImage     string `json:"product_image"`
	PurchaseToken    string `json:"purchase_token"`
}

func CreateOTPProfile(w http.ResponseWriter, r *http.Request) {
	var req CreateOTPProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Validate Payment
	isEligible := checkUserEligibility(user)
	if !isEligible {
		if req.PurchaseToken == "" {
			http.Error(w, "Payment required. Free trial already used.", http.StatusPaymentRequired)
			return
		}
		if playStoreVerifier != nil && playStoreVerifier.Enabled() {
			if err := playStoreVerifier.VerifySubscriptionPurchase(r.Context(), req.PurchaseToken); err != nil {
				http.Error(w, "Payment verification failed: "+err.Error(), http.StatusPaymentRequired)
				return
			}
		}
	}

	otp := models.OTPProfile{
		OwnerID:          user.ID,
		ChampionName:     req.ChampionName,
		Description:      req.Description,
		SubscriptionPlan: req.SubscriptionPlan,
		ProductName:      req.ProductName,
		ProductImage:     req.ProductImage,
		PrivateJSONData:  "{}",
		IsActive:         true, // Active immediately for Free Month
	}

	if err := database.DB.Create(&otp).Error; err != nil {
		http.Error(w, "Failed to create OTP profile", http.StatusInternalServerError)
		return
	}

	if user.Role != "entrepreneur" {
		user.Role = "entrepreneur"
	}
	
	if isEligible && req.PurchaseToken == "" {
		user.HasUsedCreatorTrial = true
	}
	database.DB.Save(user)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(otp)
}

// CheckEligibility checks if the user is eligible for the first month free
func CheckEligibility(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	eligible := checkUserEligibility(user)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"eligible": eligible})
}
