package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
	"github.com/go-chi/chi/v5"
)

type CreateGroupDraftRequest struct {
	Name             string `json:"name"`
	SubscriptionPlan string `json:"subscription_plan"`
}

func CreateGroupDraft(w http.ResponseWriter, r *http.Request) {
	var req CreateGroupDraftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Prevent multiple enterprises (even drafts)
	var existingGroup models.Group
	if err := database.DB.Where("owner_id = ?", user.ID).First(&existingGroup).Error; err == nil {
		if existingGroup.Status == "draft" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK) // Return existing draft
			json.NewEncoder(w).Encode(existingGroup)
			return
		}
		http.Error(w, "You already have a Group. Please upgrade or manage your existing plan.", http.StatusConflict)
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
		SubscriptionPlan: req.SubscriptionPlan,
		Status:           "draft",
		IsActive:         false,
		PrivateJSONData:  "{}",
	}

	if err := database.DB.Create(&group).Error; err != nil {
		http.Error(w, "Failed to create group draft: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(group)
}

// GetMyDraft fetches the current user's draft group if it exists
func GetMyDraft(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var group models.Group
	if err := database.DB.Preload("GroupInvitations").Where("owner_id = ? AND status = 'draft'", user.ID).First(&group).Error; err != nil {
		http.Error(w, "Draft not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(group)
}

type UpdateGroupDraftRequest struct {
	Name             string   `json:"name"`
	ProductName      string   `json:"product_name"`
	ProductImage     string   `json:"product_image"`
	Description      string   `json:"description"`
	SubscriptionPlan string   `json:"subscription_plan"`
	Invites          []string `json:"invites"`
}

func UpdateGroupDraft(w http.ResponseWriter, r *http.Request) {
	groupID := chi.URLParam(r, "id")
	if groupID == "" {
		http.Error(w, "Group ID is required", http.StatusBadRequest)
		return
	}

	var req UpdateGroupDraftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var group models.Group
	if err := database.DB.Where("id = ? AND owner_id = ?", groupID, user.ID).First(&group).Error; err != nil {
		http.Error(w, "Draft not found or unauthorized", http.StatusNotFound)
		return
	}

	if group.Status != "draft" {
		http.Error(w, "Only draft groups can be updated here", http.StatusBadRequest)
		return
	}

	// Update Group Fields
	group.Name = req.Name
	group.ProductName = req.ProductName
	group.ProductImage = req.ProductImage
	group.Description = req.Description
	group.SubscriptionPlan = req.SubscriptionPlan
	database.DB.Save(&group)

	// Process Invites (Add new ones, ignore existing)
	for _, email := range req.Invites {
		var existingInvite models.GroupInvitation
		err := database.DB.Where("group_id = ? AND email = ?", group.ID, email).First(&existingInvite).Error
		if err != nil {
			// Doesn't exist, create it
			newInvite := models.GroupInvitation{
				GroupID:   group.ID,
				Email:     email,
				Status:    "pending",
				ExpiresAt: time.Now().Add(7 * 24 * time.Hour), // 7 days expiration
			}
			database.DB.Create(&newInvite)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}

// PublishGroupDraft handles the final checkout and validation
func PublishGroupDraft(w http.ResponseWriter, r *http.Request) {
	groupID := chi.URLParam(r, "id")
	if groupID == "" {
		http.Error(w, "Group ID is required", http.StatusBadRequest)
		return
	}

	// Read original CreateGroupRequest fields like PurchaseToken, ProductID
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

	var group models.Group
	if err := database.DB.Where("id = ? AND owner_id = ?", groupID, user.ID).First(&group).Error; err != nil {
		http.Error(w, "Draft not found or unauthorized", http.StatusNotFound)
		return
	}

	if group.Status != "draft" {
		http.Error(w, "Group is not in draft status", http.StatusBadRequest)
		return
	}

	// 1. Check if required invites are accepted
	requiredInvites := 5
	if group.SubscriptionPlan == "300" || group.SubscriptionPlan == "300.0" || group.SubscriptionPlan == "300.00" {
		requiredInvites = 15
	} else if group.SubscriptionPlan == "500" || group.SubscriptionPlan == "500.0" || group.SubscriptionPlan == "500.00" {
		requiredInvites = 20
	}

	var acceptedCount int64
	database.DB.Model(&models.GroupInvitation{}).Where("group_id = ? AND status = 'accepted'", group.ID).Count(&acceptedCount)

	isAdmin := (user.Email == "darlyndavid100@gmail.com")
	if !isAdmin && int(acceptedCount) < requiredInvites {
		http.Error(w, "Not enough members have accepted the invitation for the selected plan", http.StatusBadRequest)
		return
	}

	// 2. Validate Payment / Eligibility (reused logic from CreateGroup)
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

	// Publish the group!
	group.Status = "active"
	group.IsActive = true
	group.PurchaseToken = purchaseToken
	database.DB.Save(&group)

	// Save transaction, etc. (Copied from CreateGroup)
	tx := models.PaymentTransaction{
		UserID:        user.ID,
		PlanID:        req.ProductID,
		ProductID:     req.ProductID,
		PurchaseToken: purchaseToken,
		Amount:        getPriceForProduct(req.ProductID),
		Status:        "completed",
	}
	database.DB.Create(&tx)

	// If using free trial, mark it as used
	if isEligible && req.PurchaseToken == "" {
		user.HasUsedCreatorTrial = true
		database.DB.Save(user)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(group)
}
