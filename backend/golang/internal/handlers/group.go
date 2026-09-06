package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"

	"backend/internal/database"
	"backend/internal/gemini"
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
	if !ok {
		http.Error(w, "Unauthorized. User not found in context.", http.StatusUnauthorized)
		return
	}

	if user.Banned {
		http.Error(w, "Cuenta suspendida permanentemente por múltiples infracciones", http.StatusForbidden)
		return
	}

	if len(req.Rules) > 5000 {
		http.Error(w, "Las reglas exceden el límite permitido de 5000 caracteres.", http.StatusBadRequest)
		return
	}

	// Moderate Text using Gemini
	approved, reason, err := gemini.ModerateText(r.Context(), req.Rules)
	if err != nil {
		http.Error(w, "Error al moderar el contenido", http.StatusInternalServerError)
		return
	}

	if !approved {
		user.Strikes++
		if user.Strikes >= 5 {
			user.Banned = true
		}
		database.DB.Save(user)

		msg := fmt.Sprintf("Contenido rechazado. Razón: %s. Strike %d/5.", reason, user.Strikes)
		if user.Banned {
			msg = "Cuenta suspendida permanentemente por acumular 5 strikes."
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error":   true,
			"message": msg,
			"strikes": user.Strikes,
			"banned":  user.Banned,
		})
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
	ProductID        string   `json:"product_id"`
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
	// Validate Subscription Plan
	allowedGroupPlans := map[string]bool{"100": true, "300": true, "500": true, "100.0": true, "100.00": true, "300.0": true, "300.00": true, "500.0": true, "500.00": true}
	if !allowedGroupPlans[req.SubscriptionPlan] {
		http.Error(w, "Invalid subscription plan", http.StatusBadRequest)
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
	
	if req.PurchaseToken == "" && !isEligible {
		http.Error(w, "Payment required. You are not eligible for a free trial.", http.StatusPaymentRequired)
		return
	}
	
	if req.ProductID == "" {
		http.Error(w, "Product ID must be provided.", http.StatusBadRequest)
		return
	}

	purchaseToken := req.PurchaseToken
	if purchaseToken == "" {
		purchaseToken = "trial_grp_" + user.ID.String() + "_" + time.Now().Format("20060102150405")
	}
	
	if playStoreVerifier != nil && playStoreVerifier.Enabled() && req.PurchaseToken != "" {
		// Enforces that the purchase token belongs to the given product ID
		if _, err := playStoreVerifier.VerifySubscriptionPurchase(r.Context(), req.ProductID, req.PurchaseToken); err != nil {
			http.Error(w, "Payment verification failed: "+err.Error(), http.StatusPaymentRequired)
			return
		}
	}

	// Security Check: Prevent PurchaseToken reuse (Replay Attack)
	var existingTx models.PaymentTransaction
	if err := database.DB.Where("purchase_token = ?", purchaseToken).First(&existingTx).Error; err == nil {
		http.Error(w, "Este recibo de compra ya ha sido procesado anteriormente. No puedes reusarlo.", http.StatusConflict)
		return
	}

	// 3. Enforce Single Enterprise Rule
	var existingGroup models.Group
	if err := database.DB.Where("owner_id = ?", user.ID).First(&existingGroup).Error; err == nil {
		http.Error(w, "You already have a Group. Please upgrade your existing plan instead.", http.StatusConflict)
		return
	}
	var existingOTP models.OTPProfile
	if err := database.DB.Where("owner_id = ?", user.ID).First(&existingOTP).Error; err == nil {
		http.Error(w, "You already have an OTP profile. Please upgrade or migrate to a Group instead.", http.StatusConflict)
		return
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
		PurchaseToken:    req.PurchaseToken,
	}

	if err := database.DB.Create(&group).Error; err != nil {
		http.Error(w, "Failed to create group", http.StatusInternalServerError)
		return
	}

	// Record the payment in PaymentTransaction so RTDN knows who this belongs to
	paymentTx := models.PaymentTransaction{
		UserID:        user.ID,
		PlanID:        req.ProductID,
		ProductID:     req.ProductID,
		PurchaseToken: req.PurchaseToken,
		Amount:        getPriceForProduct(req.ProductID),
		Status:        "completed",
	}
	database.DB.Create(&paymentTx)

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
	
	if isEligible {
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
	ProductID        string `json:"product_id"`
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
	// Validate Subscription Plan
	allowedOTPPlans := map[string]bool{"10": true, "30": true, "50": true, "10.0": true, "10.00": true, "30.0": true, "30.00": true, "50.0": true, "50.00": true}
	if !allowedOTPPlans[req.SubscriptionPlan] {
		http.Error(w, "Invalid subscription plan", http.StatusBadRequest)
		return
	}

	// Validate Payment
	isEligible := checkUserEligibility(user)
	
	if req.PurchaseToken == "" && !isEligible {
		http.Error(w, "Payment required. You are not eligible for a free trial.", http.StatusPaymentRequired)
		return
	}
	
	if req.ProductID == "" {
		http.Error(w, "Product ID must be provided.", http.StatusBadRequest)
		return
	}
	
	if playStoreVerifier != nil && playStoreVerifier.Enabled() && req.PurchaseToken != "" {
		// Enforces that the purchase token belongs to the given product ID
		if _, err := playStoreVerifier.VerifySubscriptionPurchase(r.Context(), req.ProductID, req.PurchaseToken); err != nil {
			http.Error(w, "Payment verification failed: "+err.Error(), http.StatusPaymentRequired)
			return
		}
	}

	purchaseToken := req.PurchaseToken
	if purchaseToken == "" {
		purchaseToken = "trial_otp_" + user.ID.String() + "_" + time.Now().Format("20060102150405")
	}

	// Security Check: Prevent PurchaseToken reuse (Replay Attack)
	var existingTx models.PaymentTransaction
	if err := database.DB.Where("purchase_token = ?", purchaseToken).First(&existingTx).Error; err == nil {
		http.Error(w, "Este recibo de compra ya ha sido procesado anteriormente. No puedes reusarlo.", http.StatusConflict)
		return
	}

	// Enforce Single Enterprise Rule
	var existingGroup models.Group
	if err := database.DB.Where("owner_id = ?", user.ID).First(&existingGroup).Error; err == nil {
		http.Error(w, "You already have a Group. Please upgrade your existing plan instead.", http.StatusConflict)
		return
	}
	var existingOTP models.OTPProfile
	if err := database.DB.Where("owner_id = ?", user.ID).First(&existingOTP).Error; err == nil {
		http.Error(w, "You already have an OTP profile. Please upgrade your existing plan instead.", http.StatusConflict)
		return
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
		PurchaseToken:    purchaseToken,
	}

	if err := database.DB.Create(&otp).Error; err != nil {
		http.Error(w, "Failed to create OTP profile", http.StatusInternalServerError)
		return
	}

	// Record the payment in PaymentTransaction so RTDN knows who this belongs to
	paymentTx := models.PaymentTransaction{
		UserID:        user.ID,
		PlanID:        req.ProductID,
		ProductID:     req.ProductID,
		PurchaseToken: purchaseToken,
		Amount:        getPriceForProduct(req.ProductID),
		Status:        "completed",
	}
	database.DB.Create(&paymentTx)

	if user.Role != "entrepreneur" {
		user.Role = "entrepreneur"
	}
	
	if isEligible {
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
