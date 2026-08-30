package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"backend/internal/config"
	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
	"backend/internal/playstore"

	"gorm.io/gorm"
)

var playStoreVerifier *playstore.Verifier

func InitSubscriptionHandlers() {
	verifier, err := playstore.NewVerifier()
	if err != nil {
		if strings.EqualFold(config.GetEnv("GOOGLE_PLAY_VERIFICATION_ENABLED", "false"), "true") {
			log.Fatalf("Google Play verifier init failed: %v", err)
		}
		log.Printf("Google Play verifier not initialized: %v", err)
	}
	playStoreVerifier = verifier
}

type VerifyPurchaseRequest struct {
	ProductID     string `json:"product_id"`
	PurchaseToken string `json:"purchase_token"`
}

type SubscriptionStatusResponse struct {
	HasActiveSubscription bool       `json:"has_active_subscription"`
	GlobalFreeTrialActive bool       `json:"global_free_trial_active"`
	CanAccessService      bool       `json:"can_access_service"`
	EndsAt                *time.Time `json:"ends_at"`
}

func isUnverifiedPurchaseAllowed() bool {
	return strings.EqualFold(config.GetEnv("ALLOW_UNVERIFIED_PURCHASES", "false"), "true") &&
		!strings.EqualFold(config.GetEnv("ENV", "development"), "production")
}

func verifyPurchaseToken(r *http.Request, productID, purchaseToken string) error {
	purchaseToken = strings.TrimSpace(purchaseToken)
	if purchaseToken == "" {
		return fmt.Errorf("purchase token is required")
	}

	if playStoreVerifier != nil && playStoreVerifier.Enabled() {
		return playStoreVerifier.VerifyProductPurchase(r.Context(), productID, purchaseToken)
	}

	if isUnverifiedPurchaseAllowed() {
		return nil
	}

	return fmt.Errorf("purchase verification required; enable GOOGLE_PLAY_VERIFICATION_ENABLED or set ALLOW_UNVERIFIED_PURCHASES=true in non-production")
}

func VerifyPurchase(w http.ResponseWriter, r *http.Request) {
	var req VerifyPurchaseRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	duration := getDurationForProduct(req.ProductID)
	planID, hasPlan := getPlanIDForProduct(req.ProductID)
	if duration == 0 || !hasPlan {
		http.Error(w, "Invalid product ID", http.StatusBadRequest)
		return
	}

	purchaseToken := strings.TrimSpace(req.PurchaseToken)

	// Idempotency: if this token was already processed, return current subscription.
	var existing models.PaymentTransaction
	if err := database.DB.Where("purchase_token = ?", purchaseToken).First(&existing).Error; err == nil {
		if existing.Status == "completed" {
			var currentUser models.User
			if err := database.DB.First(&currentUser, user.ID).Error; err != nil {
				http.Error(w, "Failed to load user", http.StatusInternalServerError)
				return
			}
			writeVerifySuccess(w, currentUser.SubscriptionEndsAt)
			return
		}
		http.Error(w, "Purchase token already used", http.StatusConflict)
		return
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		http.Error(w, "Failed to check purchase history", http.StatusInternalServerError)
		return
	}

	if err := verifyPurchaseToken(r, req.ProductID, purchaseToken); err != nil {
		_ = database.DB.Create(&models.PaymentTransaction{
			UserID:        user.ID,
			PlanID:        req.ProductID,
			ProductID:     req.ProductID,
			PurchaseToken: purchaseToken,
			Amount:        getPriceForProduct(req.ProductID),
			Status:        "failed",
		}).Error
		http.Error(w, err.Error(), http.StatusPaymentRequired)
		return
	}

	tx := database.DB.Begin()
	if tx.Error != nil {
		http.Error(w, "Failed to start transaction", http.StatusInternalServerError)
		return
	}

	transaction := models.PaymentTransaction{
		UserID:        user.ID,
		PlanID:        req.ProductID,
		ProductID:     req.ProductID,
		PurchaseToken: purchaseToken,
		Amount:        getPriceForProduct(req.ProductID),
		Status:        "completed",
	}
	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to record payment", http.StatusInternalServerError)
		return
	}

	var dbUser models.User
	if err := tx.First(&dbUser, user.ID).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to load user", http.StatusInternalServerError)
		return
	}

	now := time.Now()
	if dbUser.SubscriptionEndsAt != nil && dbUser.SubscriptionEndsAt.After(now) {
		newEndsAt := dbUser.SubscriptionEndsAt.Add(duration)
		dbUser.SubscriptionEndsAt = &newEndsAt
	} else {
		newEndsAt := now.Add(duration)
		dbUser.SubscriptionEndsAt = &newEndsAt
	}
	dbUser.ActivePlan = &planID

	if err := tx.Save(&dbUser).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to update subscription", http.StatusInternalServerError)
		return
	}

	if err := tx.Commit().Error; err != nil {
		http.Error(w, "Failed to commit subscription update", http.StatusInternalServerError)
		return
	}

	writeVerifySuccess(w, dbUser.SubscriptionEndsAt)
}

func writeVerifySuccess(w http.ResponseWriter, endsAt *time.Time) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"ends_at": endsAt,
	})
}

func GetSubscriptionStatus(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	hasActive := false
	var activePlan string = "freemium"

	if user.SubscriptionEndsAt != nil && time.Now().Before(*user.SubscriptionEndsAt) {
		hasActive = true
		if user.ActivePlan != nil {
			activePlan = *user.ActivePlan
		}
	}

	globalFreeTrialActive := middleware.IsGlobalFreeTrialActive()
	
	// If global free trial is active and user is not paying, they get the "plus" plan
	if globalFreeTrialActive && !hasActive {
		activePlan = "plus"
	}

	canAccess := hasActive || globalFreeTrialActive

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"has_active_subscription": hasActive,
		"global_free_trial_active": globalFreeTrialActive,
		"can_access_service":      canAccess,
		"ends_at":                user.SubscriptionEndsAt,
		"plan_name":               activePlan,
	})
}
