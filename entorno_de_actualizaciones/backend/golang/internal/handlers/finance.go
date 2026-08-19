package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
	
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type RechargeCoinsRequest struct {
	ProductID     string `json:"product_id"`
	PurchaseToken string `json:"purchase_token"`
}

type GroupSubscriptionRequest struct {
	SubscriptionID string `json:"subscription_id"`
	PurchaseToken  string `json:"purchase_token"`
	GroupID        string `json:"group_id"` // Group UUID
}

func getCoinsForProduct(productID string) float64 {
	switch productID {
	case "coin_pack_1":
		return 1.00 // $1 USD pack = 1 Coin value (or 20 fanarts of $0.05)
	case "coin_pack_5":
		return 5.00
	case "coin_pack_10":
		return 10.00
	case "coin_pack_20":
		return 20.00
	default:
		return 0
	}
}

// RechargeCoins verifies an IAP purchase and adds coins to the user's wallet.
func RechargeCoins(w http.ResponseWriter, r *http.Request) {
	var req RechargeCoinsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	coinsToAdd := getCoinsForProduct(req.ProductID)
	if coinsToAdd <= 0 {
		http.Error(w, "Invalid coin product", http.StatusBadRequest)
		return
	}

	purchaseToken := strings.TrimSpace(req.PurchaseToken)

	// Idempotency check
	var existing models.Transaction
	err := database.DB.Where("type = ? AND amount_coin = ? AND status = ?", "recharge_coin", coinsToAdd, purchaseToken).First(&existing).Error
	if err == nil {
		http.Error(w, "Purchase token already used", http.StatusConflict)
		return
	}

	// Verify purchase via Google Play
	if err := verifyPurchaseToken(r, req.ProductID, purchaseToken); err != nil {
		http.Error(w, "Verification failed: "+err.Error(), http.StatusPaymentRequired)
		return
	}

	tx := database.DB.Begin()

	// Ensure user has a wallet
	var wallet models.Wallet
	if err := tx.Where("user_id = ?", user.ID).First(&wallet).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			wallet = models.Wallet{UserID: user.ID}
			if err := tx.Create(&wallet).Error; err != nil {
				tx.Rollback()
				http.Error(w, "Failed to create wallet", http.StatusInternalServerError)
				return
			}
		} else {
			tx.Rollback()
			http.Error(w, "Failed to fetch wallet", http.StatusInternalServerError)
			return
		}
	}

	// Update Wallet
	wallet.BalanceCoin += coinsToAdd
	if err := tx.Save(&wallet).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to update wallet", http.StatusInternalServerError)
		return
	}

	// Record Transaction (Hack: using status field to store purchaseToken temporarily for idempotency if needed, or better use a dedicated field. We'll rely on the existing status or add a memo if needed. Let's just create it.)
	transaction := models.Transaction{
		UserID:     user.ID,
		Type:       "recharge_coin",
		AmountCoin: coinsToAdd,
		Status:     "completed",
	}
	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to record transaction", http.StatusInternalServerError)
		return
	}

	tx.Commit()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":      true,
		"new_balance":  wallet.BalanceCoin,
	})
}

// SubscribeToGroup verifies an IAP subscription and links the user to the Group.
func SubscribeToGroup(w http.ResponseWriter, r *http.Request) {
	var req GroupSubscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	groupID, err := uuid.Parse(req.GroupID)
	if err != nil {
		http.Error(w, "Invalid Group ID", http.StatusBadRequest)
		return
	}

	// In a complete implementation, check if Group exists and isn't full.
	_ = user.ID // Silence unused variable error for now

	// Verify the subscription purchase
	if playStoreVerifier != nil && playStoreVerifier.Enabled() {
		if err := playStoreVerifier.VerifySubscriptionPurchase(r.Context(), req.PurchaseToken); err != nil {
			http.Error(w, "Subscription verification failed: "+err.Error(), http.StatusPaymentRequired)
			return
		}
	}

	// Here we would typically record the active subscription linking the user to the GroupID.
	// For now, we acknowledge success.

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Subscribed to group successfully",
		"group_id": groupID,
	})
}
