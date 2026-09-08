package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"net/http"
	"strconv"
	"strings"
	"time"

	"backend/internal/config"
	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"github.com/stripe/stripe-go/v78"
	"github.com/stripe/stripe-go/v78/transfer"
)

type RechargeCoinsRequest struct {
	ProductID     string `json:"product_id"`
	PurchaseToken string `json:"purchase_token"`
}

func getPlanSplitPercentage(plan string) float64 {
	// Remove possible formatting
	p := strings.ReplaceAll(plan, "$", "")
	p = strings.ReplaceAll(p, ".0", "")
	p = strings.ReplaceAll(p, ".00", "")
	p = strings.TrimSpace(p)
	
	switch p {
	case "10", "100":
		return 0.50
	case "30", "300":
		return 0.70
	case "50", "500":
		return 0.90
	default:
		return 0.50 // Default 50%
	}
}

type GroupSubscriptionRequest struct {
	SubscriptionID string `json:"subscription_id"`
	PurchaseToken  string `json:"purchase_token"`
	GroupID        string `json:"group_id"` // Group UUID
}

func getEssenceForProduct(productID string) float64 {
	switch productID {
	case "essence_pack_250":
		return 250.00 // $0.25 USD pack = 250 Blue Essences
	case "essence_pack_500":
		return 500.00 // $0.50 USD pack = 500 Blue Essences
	case "essence_pack_1000":
		return 1000.00 // $1.00 USD pack = 1000 Blue Essences
	case "essence_pack_3000":
		return 3000.00 // $3.00 USD pack = 3000 Blue Essences
	case "essence_pack_5000":
		return 5000.00 // $5.00 USD pack = 5000 Blue Essences
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

	essenceToAdd := getEssenceForProduct(req.ProductID)
	if essenceToAdd <= 0 {
		http.Error(w, "Invalid coin product", http.StatusBadRequest)
		return
	}

	purchaseToken := strings.TrimSpace(req.PurchaseToken)
	
	// Create a hash of the token for idempotency check to avoid DB column size limits truncating the Google Play token
	hash := sha256.Sum256([]byte(purchaseToken))
	tokenHash := hex.EncodeToString(hash[:])

	// Idempotency check (early exit, real check is DB unique constraint)
	var existing models.Transaction
	err := database.DB.Where("purchase_token = ?", tokenHash).First(&existing).Error
	if err == nil {
		http.Error(w, "Purchase token already used", http.StatusConflict)
		return
	}

	// Rate limiting: 10 daily purchases per user
	var dailyPurchases int64
	today := time.Now().Truncate(24 * time.Hour)
	database.DB.Model(&models.Transaction{}).Where("user_id = ? AND type = 'recharge_essence' AND created_at >= ?", user.ID, today).Count(&dailyPurchases)
	if dailyPurchases >= 10 {
		http.Error(w, "Daily purchase limit reached (max 10)", http.StatusTooManyRequests)
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
	if err := tx.Model(&wallet).UpdateColumn("balance_essence", gorm.Expr("balance_essence + ?", essenceToAdd)).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to update wallet", http.StatusInternalServerError)
		return
	}

	// Record Transaction
	transaction := models.Transaction{
		UserID:        user.ID,
		Type:          "recharge_essence",
		AmountEssence: essenceToAdd,
		Status:        "completed",
		PurchaseToken: &tokenHash,
	}
	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		if strings.Contains(err.Error(), "duplicate key value") || strings.Contains(err.Error(), "unique constraint") {
			http.Error(w, "Purchase token already used", http.StatusConflict)
		} else {
			http.Error(w, "Failed to record transaction", http.StatusInternalServerError)
		}
		return
	}

	tx.Commit()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":     true,
		"new_balance": wallet.BalanceEssence,
	})
}

// SubscribeToGroup verifies an IAP subscription and links the user to the Group.
// Includes the mathematical distribution of Net Profit.
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

	purchaseToken := strings.TrimSpace(req.PurchaseToken)
	hash := sha256.Sum256([]byte(purchaseToken))
	tokenHash := hex.EncodeToString(hash[:])

	// Idempotency check
	var existing models.Transaction
	if err := database.DB.Where("purchase_token = ?", tokenHash).First(&existing).Error; err == nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": "Already subscribed.",
		})
		return
	}
	var existingPayment models.PaymentTransaction
	if err := database.DB.Where("purchase_token = ?", purchaseToken).First(&existingPayment).Error; err == nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": "Already subscribed (PaymentTransaction).",
		})
		return
	}

	// Fetch Group to calculate splits
	var group models.Group
	if err := database.DB.Where("id = ?", groupID).First(&group).Error; err != nil {
		http.Error(w, "Group not found", http.StatusNotFound)
		return
	}

	// Verify owner's subscription is active
	var owner models.User
	if err := database.DB.Where("id = ?", group.OwnerID).First(&owner).Error; err != nil {
		http.Error(w, "Group owner not found", http.StatusInternalServerError)
		return
	}
	if owner.SubscriptionEndsAt == nil || time.Now().After(*owner.SubscriptionEndsAt) {
		http.Error(w, "Este producto actualmente se encuentra suspendido y no admite nuevas suscripciones.", http.StatusForbidden)
		return
	}

	// Verify the subscription purchase
	if playStoreVerifier != nil && playStoreVerifier.Enabled() {
		if _, err := playStoreVerifier.VerifySubscriptionPurchase(r.Context(), req.SubscriptionID, req.PurchaseToken); err != nil {
			http.Error(w, "Subscription verification failed: "+err.Error(), http.StatusPaymentRequired)
			return
		}
	}

	// --- MATHEMATICAL SPLIT LOGIC ---
	// 1. Gross Revenue (from the consumer's chosen plan)
	gross := getPriceForProduct(req.SubscriptionID)
	if gross <= 0 {
		gross = 9.99 // Default fallback
	}

	// 2. Google Play Commission (15%)
	netFromGoogle := gross * 0.85

	// 3. Plan Split calculation
	entSplit := getPlanSplitPercentage(group.SubscriptionPlan)
	appSplit := 1.0 - entSplit
	
	appShare := netFromGoogle * appSplit
	entrepreneurShare := netFromGoogle * entSplit

	// 4. Gemini API Cost deduction (Dynamic cost)
	planPrice := 0.0
	if parsed, err := strconv.ParseFloat(group.SubscriptionPlan, 64); err == nil {
		planPrice = parsed
	}
	// For Groups: 0.05 + (price * 0.0005)
	geminiPercentage := 0.05 + (planPrice * 0.0005)
	apiCost := gross * geminiPercentage
	finalEntrepreneurPayout := entrepreneurShare - apiCost

	tx := database.DB.Begin()

	// Find all accepted members
	var invitations []models.GroupInvitation
	if err := tx.Where("group_id = ? AND status = ?", groupID, "accepted").Find(&invitations).Error; err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		tx.Rollback()
		http.Error(w, "Error fetching group members", http.StatusInternalServerError)
		return
	}

	// The total members = Owner + accepted members
	var memberEmails []string
	memberEmails = append(memberEmails, user.Email) // wait, the owner email? No, we just need their IDs.
	
	// Collect all user IDs that are part of the group
	memberIDs := []uuid.UUID{group.OwnerID}
	
	for _, inv := range invitations {
		var member models.User
		if err := tx.Where("email = ?", inv.Email).First(&member).Error; err == nil {
			memberIDs = append(memberIDs, member.ID)
		}
	}

	// Split equitativamente
	splitAmount := finalEntrepreneurPayout / float64(len(memberIDs))

	for _, mID := range memberIDs {
		var wallet models.Wallet
		if err := tx.Where("user_id = ?", mID).First(&wallet).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				wallet = models.Wallet{UserID: mID}
				tx.Create(&wallet)
			}
		}
		tx.Model(&wallet).UpdateColumn("balance_usd", gorm.Expr("balance_usd + ?", splitAmount))

		// Record Transaction for each member
		transaction := models.Transaction{
			UserID:    mID,
			Type:      "subscription_payout",
			AmountUSD: splitAmount,
			Status:    "completed",
		}
		tx.Create(&transaction)
	}

	// Update App's internal ledger (optional, we keep our share intact)
	_ = appShare

	// Record purchase for Consumer so it shows in My Packages
	buyerTx := models.Transaction{
		UserID:          user.ID,
		Type:            "purchase_ai_package",
		AmountUSD:       gross, // What the buyer paid
		RelatedEntityID: &groupID,
		Status:          "completed",
		PurchaseToken:   &tokenHash,
	}
	if err := tx.Create(&buyerTx).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Transaction processing failed or token reused.", http.StatusConflict)
		return
	}

	// Create a PaymentTransaction in plain text so Webhooks (RTDN) can renew this subscription
	paymentTx := models.PaymentTransaction{
		UserID:        user.ID,
		PlanID:        req.SubscriptionID,
		ProductID:     req.SubscriptionID,
		PurchaseToken: purchaseToken,
		Amount:        gross,
		Status:        "completed",
	}
	if err := tx.Create(&paymentTx).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Payment transaction record failed.", http.StatusInternalServerError)
		return
	}

	// Grant Esencias Azules based on the exact product purchased (Only Global Plans have bonuses now)
	var essenceBonus float64 = 0
	switch req.SubscriptionID {
	case "sub_plus_1d":
		essenceBonus = 0.0 // No bonus for daily plus
	case "sub_pro_1d":
		essenceBonus = 50.0
	case "sub_ultra_1d":
		essenceBonus = 100.0
	case "sub_plus_1w":
		essenceBonus = 150.0
	case "sub_pro_1w":
		essenceBonus = 300.0
	case "sub_ultra_1w":
		essenceBonus = 600.0
	case "sub_plus_1m":
		essenceBonus = 600.0
	case "sub_pro_1m":
		essenceBonus = 1000.0
	case "sub_ultra_1m":
		essenceBonus = 2000.0
	case "sub_plus_1y":
		essenceBonus = 6000.0
	case "sub_pro_1y":
		essenceBonus = 10000.0
	case "sub_ultra_1y":
		essenceBonus = 20000.0
	}

	if essenceBonus > 0 {
		var buyerWallet models.Wallet
		if err := tx.Where("user_id = ?", user.ID).First(&buyerWallet).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				buyerWallet = models.Wallet{UserID: user.ID}
				tx.Create(&buyerWallet)
			}
		}
		tx.Model(&buyerWallet).UpdateColumn("balance_essence", gorm.Expr("balance_essence + ?", essenceBonus))

		bonusTx := models.Transaction{
			UserID:        user.ID,
			Type:          "subscription_bonus",
			AmountEssence: essenceBonus,
			Status:        "completed",
		}
		tx.Create(&bonusTx)
	}

	// Record the active subscription linking the user to the GroupID.
	user.ActiveGroupID = &groupID
	
	// Update buyer's subscription expiration and active plan
	duration := getDurationForProduct(req.SubscriptionID)
	planID, hasPlan := getPlanIDForProduct(req.SubscriptionID)
	
	if hasPlan {
		now := time.Now()
		if user.SubscriptionEndsAt != nil && user.SubscriptionEndsAt.After(now) {
			newEndsAt := user.SubscriptionEndsAt.Add(duration)
			user.SubscriptionEndsAt = &newEndsAt
		} else {
			newEndsAt := now.Add(duration)
			user.SubscriptionEndsAt = &newEndsAt
		}
		user.ActivePlan = &planID
	}

	if err := tx.Save(user).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to link user to group and update subscription", http.StatusInternalServerError)
		return
	}

	tx.Commit()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":  true,
		"message":  "Subscribed to group successfully. Financials calculated.",
		"group_id": groupID,
	})
}

type CreatorSubscriptionRequest struct {
	SubscriptionID string `json:"subscription_id"`
	PurchaseToken  string `json:"purchase_token"`
	CreatorID      string `json:"creator_id"` // CreatorProfile UUID
}

// SubscribeToCreator verifies an IAP subscription and links the user to the Creator's AI package.
func SubscribeToCreator(w http.ResponseWriter, r *http.Request) {
	var req CreatorSubscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	profileID, err := uuid.Parse(req.CreatorID)
	if err != nil {
		http.Error(w, "Invalid Creator ID", http.StatusBadRequest)
		return
	}

	purchaseToken := strings.TrimSpace(req.PurchaseToken)
	hash := sha256.Sum256([]byte(purchaseToken))
	tokenHash := hex.EncodeToString(hash[:])

	// Idempotency check
	var existing models.Transaction
	if err := database.DB.Where("purchase_token = ?", tokenHash).First(&existing).Error; err == nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": "Already subscribed.",
		})
		return
	}
	var existingPayment models.PaymentTransaction
	if err := database.DB.Where("purchase_token = ?", purchaseToken).First(&existingPayment).Error; err == nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": "Already subscribed (PaymentTransaction).",
		})
		return
	}

	// Fetch OTPProfile to find owner
	var profile models.OTPProfile
	if err := database.DB.Where("id = ?", profileID).First(&profile).Error; err != nil {
		http.Error(w, "Creator profile not found", http.StatusNotFound)
		return
	}

	// Verify owner's subscription is active
	var owner models.User
	if err := database.DB.Where("id = ?", profile.OwnerID).First(&owner).Error; err != nil {
		http.Error(w, "Creator owner not found", http.StatusInternalServerError)
		return
	}
	if owner.SubscriptionEndsAt == nil || time.Now().After(*owner.SubscriptionEndsAt) {
		http.Error(w, "Este producto actualmente se encuentra suspendido y no admite nuevas suscripciones.", http.StatusForbidden)
		return
	}

	// Verify the subscription purchase
	if playStoreVerifier != nil && playStoreVerifier.Enabled() {
		if _, err := playStoreVerifier.VerifySubscriptionPurchase(r.Context(), req.SubscriptionID, req.PurchaseToken); err != nil {
			http.Error(w, "Subscription verification failed: "+err.Error(), http.StatusPaymentRequired)
			return
		}
	}

	// --- MATHEMATICAL SPLIT LOGIC ---
	gross := getPriceForProduct(req.SubscriptionID)
	if gross <= 0 {
		gross = 4.99 // Default fallback for AI Package
	}

	netFromGoogle := gross * 0.85

	entSplit := getPlanSplitPercentage(profile.SubscriptionPlan)
	appSplit := 1.0 - entSplit

	appShare := netFromGoogle * appSplit
	entrepreneurShare := netFromGoogle * entSplit
	planPrice := 0.0
	if parsed, err := strconv.ParseFloat(profile.SubscriptionPlan, 64); err == nil {
		planPrice = parsed
	}
	geminiPercentage := 0.05
	if strings.Contains(strings.ToLower(profile.SubscriptionPlan), "grupo") {
		geminiPercentage += (planPrice * 0.0005)
	} else {
		geminiPercentage += (planPrice * 0.005)
	}
	apiCost := gross * geminiPercentage
	finalEntrepreneurPayout := entrepreneurShare - apiCost

	tx := database.DB.Begin()

	var entWallet models.Wallet
	if err := tx.Where("user_id = ?", profile.OwnerID).First(&entWallet).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			entWallet = models.Wallet{UserID: profile.OwnerID}
			tx.Create(&entWallet)
		}
	}
	tx.Model(&entWallet).UpdateColumn("balance_usd", gorm.Expr("balance_usd + ?", finalEntrepreneurPayout))

	_ = appShare 

	// Record Transaction to pay creator
	transaction := models.Transaction{
		UserID:    profile.OwnerID,
		Type:      "subscription_payout",
		AmountUSD: finalEntrepreneurPayout,
		Status:    "completed",
	}
	tx.Create(&transaction)

	// Record purchase for Consumer so it shows in My Packages
	buyerTx := models.Transaction{
		UserID:          user.ID,
		Type:            "purchase_ai_package",
		AmountUSD:       gross, // What the buyer paid
		RelatedEntityID: &profileID,
		Status:          "completed",
		PurchaseToken:   &tokenHash,
	}
	if err := tx.Create(&buyerTx).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Transaction processing failed or token reused.", http.StatusConflict)
		return
	}

	// Create a PaymentTransaction in plain text so Webhooks (RTDN) can renew this subscription
	paymentTx := models.PaymentTransaction{
		UserID:        user.ID,
		PlanID:        req.SubscriptionID,
		ProductID:     req.SubscriptionID,
		PurchaseToken: purchaseToken,
		Amount:        gross,
		Status:        "completed",
	}
	if err := tx.Create(&paymentTx).Error; err != nil {
		tx.Rollback()
		fmt.Printf("Error creating PaymentTransaction: %v\n", err)
		http.Error(w, "Payment transaction record failed: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Grant Esencias Azules based on the exact product purchased (Only Global Plans have bonuses now)
	var essenceBonus float64 = 0
	switch req.SubscriptionID {
	case "sub_plus_1d":
		essenceBonus = 0.0 // No bonus for daily plus
	case "sub_pro_1d":
		essenceBonus = 50.0
	case "sub_ultra_1d":
		essenceBonus = 100.0
	case "sub_plus_1w":
		essenceBonus = 150.0
	case "sub_pro_1w":
		essenceBonus = 300.0
	case "sub_ultra_1w":
		essenceBonus = 600.0
	case "sub_plus_1m":
		essenceBonus = 600.0
	case "sub_pro_1m":
		essenceBonus = 1000.0
	case "sub_ultra_1m":
		essenceBonus = 2000.0
	case "sub_plus_1y":
		essenceBonus = 6000.0
	case "sub_pro_1y":
		essenceBonus = 10000.0
	case "sub_ultra_1y":
		essenceBonus = 20000.0
	}

	if essenceBonus > 0 {
		var buyerWallet models.Wallet
		if err := tx.Where("user_id = ?", user.ID).First(&buyerWallet).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				buyerWallet = models.Wallet{UserID: user.ID}
				tx.Create(&buyerWallet)
			}
		}
		tx.Model(&buyerWallet).UpdateColumn("balance_essence", gorm.Expr("balance_essence + ?", essenceBonus))

		bonusTx := models.Transaction{
			UserID:        user.ID,
			Type:          "subscription_bonus",
			AmountEssence: essenceBonus,
			Status:        "completed",
		}
		tx.Create(&bonusTx)
	}

	// Update buyer's subscription expiration and active plan
	duration := getDurationForProduct(req.SubscriptionID)
	planID, hasPlan := getPlanIDForProduct(req.SubscriptionID)
	
	if hasPlan {
		var dbUser models.User
		if err := tx.First(&dbUser, user.ID).Error; err == nil {
			now := time.Now()
			if dbUser.SubscriptionEndsAt != nil && dbUser.SubscriptionEndsAt.After(now) {
				newEndsAt := dbUser.SubscriptionEndsAt.Add(duration)
				dbUser.SubscriptionEndsAt = &newEndsAt
			} else {
				newEndsAt := now.Add(duration)
				dbUser.SubscriptionEndsAt = &newEndsAt
			}
			dbUser.ActivePlan = &planID
			tx.Save(&dbUser)
		}
	}

	tx.Commit()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":    true,
		"message":    "Subscribed to creator successfully.",
		"creator_id": profileID,
	})
}

// ProcessSubscriptionRenewal is called by the RTDN webhook when a consumer's subscription renews.
// It calculates and distributes the revenue share to the appropriate entrepreneur.
func ProcessSubscriptionRenewal(productID string, purchaseToken string) error {
	hash := sha256.Sum256([]byte(purchaseToken))
	tokenHash := hex.EncodeToString(hash[:])

	// Find the original consumer purchase transaction to determine the RelatedEntityID
	var buyerTx models.Transaction
	if err := database.DB.Where("purchase_token = ? AND type = 'purchase_ai_package'", tokenHash).First(&buyerTx).Error; err != nil {
		return err // Cannot find who this subscription belongs to
	}

	if buyerTx.RelatedEntityID == nil {
		return errors.New("transaction has no related entity")
	}
	entityID := *buyerTx.RelatedEntityID

	// Determine if it's a Group or OTP
	var group models.Group
	isGroup := database.DB.Where("id = ?", entityID).First(&group).Error == nil

	var otp models.OTPProfile
	isOTP := false
	if !isGroup {
		isOTP = database.DB.Where("id = ?", entityID).First(&otp).Error == nil
	}

	if !isGroup && !isOTP {
		return errors.New("related entity not found in group or otp")
	}

	gross := getPriceForProduct(productID)
	if gross <= 0 {
		gross = 9.99
	}
	netFromGoogle := gross * 0.85
	
	tx := database.DB.Begin()

	if isGroup {
		entSplit := getPlanSplitPercentage(group.SubscriptionPlan)
		entrepreneurShare := netFromGoogle * entSplit
		
		planPrice := 0.0
		if parsed, err := strconv.ParseFloat(group.SubscriptionPlan, 64); err == nil {
			planPrice = parsed
		}
		geminiPercentage := 0.05 + (planPrice * 0.0005)
		apiCost := gross * geminiPercentage
		finalEntrepreneurPayout := entrepreneurShare - apiCost

		// Find members
		var invitations []models.GroupInvitation
		tx.Where("group_id = ? AND status = ?", group.ID, "accepted").Find(&invitations)
		memberIDs := []uuid.UUID{group.OwnerID}
		for _, inv := range invitations {
			var member models.User
			if err := tx.Where("email = ?", inv.Email).First(&member).Error; err == nil {
				memberIDs = append(memberIDs, member.ID)
			}
		}

		splitAmount := finalEntrepreneurPayout / float64(len(memberIDs))

		for _, mID := range memberIDs {
			var wallet models.Wallet
			if err := tx.Where("user_id = ?", mID).First(&wallet).Error; err != nil {
				wallet = models.Wallet{UserID: mID}
				tx.Create(&wallet)
			}
			tx.Model(&wallet).UpdateColumn("balance_usd", gorm.Expr("balance_usd + ?", splitAmount))

			transaction := models.Transaction{
				UserID:    mID,
				Type:      "subscription_renewal_payout",
				AmountUSD: splitAmount,
				Status:    "completed",
			}
			tx.Create(&transaction)
		}
	} else if isOTP {
		entSplit := getPlanSplitPercentage(otp.SubscriptionPlan)
		entrepreneurShare := netFromGoogle * entSplit
		
		planPrice := 0.0
		if parsed, err := strconv.ParseFloat(otp.SubscriptionPlan, 64); err == nil {
			planPrice = parsed
		}
		geminiPercentage := 0.05
		if strings.Contains(strings.ToLower(otp.SubscriptionPlan), "grupo") {
			geminiPercentage += (planPrice * 0.0005)
		} else {
			geminiPercentage += (planPrice * 0.005)
		}
		apiCost := gross * geminiPercentage
		finalEntrepreneurPayout := entrepreneurShare - apiCost

		var entWallet models.Wallet
		if err := tx.Where("user_id = ?", otp.OwnerID).First(&entWallet).Error; err != nil {
			entWallet = models.Wallet{UserID: otp.OwnerID}
			tx.Create(&entWallet)
		}
		tx.Model(&entWallet).UpdateColumn("balance_usd", gorm.Expr("balance_usd + ?", finalEntrepreneurPayout))

		transaction := models.Transaction{
			UserID:    otp.OwnerID,
			Type:      "subscription_renewal_payout",
			AmountUSD: finalEntrepreneurPayout,
			Status:    "completed",
		}
		tx.Create(&transaction)
	}

	// Create Renewal PaymentTransaction for record keeping
	paymentTx := models.PaymentTransaction{
		UserID:        buyerTx.UserID,
		PlanID:        productID,
		ProductID:     productID,
		PurchaseToken: purchaseToken,
		Amount:        gross,
		Status:        "renewed",
	}
	tx.Create(&paymentTx)

	return tx.Commit().Error
}

type PurchaseFanartRequest struct {
	FanartID string `json:"fanart_id"`
}

// PurchaseFanart deducts Esencias Azules from buyer and credits USD to creator
func PurchaseFanart(w http.ResponseWriter, r *http.Request) {
	var req PurchaseFanartRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	buyer, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	fanartID, err := uuid.Parse(req.FanartID)
	if err != nil && req.FanartID != "mock_fanart_1" && req.FanartID != "mock_fanart_2" {
		http.Error(w, "Invalid Fanart ID", http.StatusBadRequest)
		return
	}

	if req.FanartID == "mock_fanart_1" {
		fanartID = uuid.MustParse("00000000-0000-0000-0000-000000000001")
	} else if req.FanartID == "mock_fanart_2" {
		fanartID = uuid.MustParse("00000000-0000-0000-0000-000000000002")
	}

	var fanart models.Fanart
	if req.FanartID == "mock_fanart_1" || req.FanartID == "mock_fanart_2" {
		fanart = models.Fanart{
			CreatorID: buyer.ID, // Just use buyer as creator for mock
			PriceEssence: 50.0,
		}
		if req.FanartID == "mock_fanart_2" {
			fanart.PriceEssence = 100.0
		}
	} else if err := database.DB.Where("id = ? AND status = ?", fanartID, "approved").First(&fanart).Error; err != nil {
		http.Error(w, "Fanart not found or not approved", http.StatusNotFound)
		return
	}

	tx := database.DB.Begin()

	var buyerWallet models.Wallet
	if err := tx.Where("user_id = ?", buyer.ID).First(&buyerWallet).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Wallet not found", http.StatusBadRequest)
		return
	}

	if buyerWallet.BalanceEssence < fanart.PriceEssence || fanart.PriceEssence <= 0 {
		tx.Rollback()
		http.Error(w, "Insufficient Esencias Azules or invalid fanart price", http.StatusPaymentRequired)
		return
	}

	var creatorWallet models.Wallet
	if err := tx.Where("user_id = ?", fanart.CreatorID).First(&creatorWallet).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			creatorWallet = models.Wallet{UserID: fanart.CreatorID}
			tx.Create(&creatorWallet)
		}
	}

	// Calculate equivalent USD (1000 Esencias Azules = $1 USD)
	// Creator takes 50% of the real USD value
	usdEarned := (fanart.PriceEssence / 1000.0) * 0.50

	// Prevent self-purchasing exploit
	if buyer.ID == fanart.CreatorID {
		tx.Rollback()
		http.Error(w, "No puedes comprar tu propio Fanart", http.StatusForbidden)
		return
	}

	// Deduct from buyer
	result := tx.Model(&buyerWallet).Where("balance_essence >= ?", fanart.PriceEssence).UpdateColumn("balance_essence", gorm.Expr("balance_essence - ?", fanart.PriceEssence))
	if result.Error != nil || result.RowsAffected == 0 {
		tx.Rollback()
		http.Error(w, "Saldo insuficiente o error de base de datos", http.StatusPaymentRequired)
		return
	}

	// Add to creator
	if err := tx.Model(&creatorWallet).UpdateColumn("balance_usd", gorm.Expr("balance_usd + ?", usdEarned)).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// Record Transaction
	txRec := models.Transaction{
		UserID:          buyer.ID,
		Type:            "purchase_fanart",
		AmountEssence:      fanart.PriceEssence,
		RelatedEntityID: &fanartID,
		Status:          "completed",
	}
	tx.Create(&txRec)

	tx.Commit()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Fanart purchased successfully",
	})
}

func CheckFanartPurchase(w http.ResponseWriter, r *http.Request) {
	fanartIDStr := r.URL.Query().Get("fanart_id")
	if fanartIDStr == "" {
		http.Error(w, "Missing fanart_id", http.StatusBadRequest)
		return
	}

	var fanartID uuid.UUID
	var err error
	if fanartIDStr == "mock_fanart_1" {
		fanartID = uuid.MustParse("00000000-0000-0000-0000-000000000001")
	} else if fanartIDStr == "mock_fanart_2" {
		fanartID = uuid.MustParse("00000000-0000-0000-0000-000000000002")
	} else {
		fanartID, err = uuid.Parse(fanartIDStr)
		if err != nil {
			http.Error(w, "Invalid Fanart ID", http.StatusBadRequest)
			return
		}
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var transaction models.Transaction
	err = database.DB.Where("user_id = ? AND type = 'purchase_fanart' AND related_entity_id = ? AND status = 'completed'", user.ID, fanartID).First(&transaction).Error
	
	hasPurchased := false
	if err == nil {
		hasPurchased = true
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"has_purchased": hasPurchased,
	})
}

type DonateVideoRequest struct {
	VideoID string  `json:"video_id"`
	Amount  float64 `json:"amount"` // Amount of Esencia Azul
}

func isTestAccount(email string) bool {
	if config.GetEnv("ALLOW_TEST_ACCOUNTS", "false") != "true" {
		return false
	}
	return email == "darlyndavid2026@gmail.com" || email == "0805409802d@gmail.com"
}

func DonateVideo(w http.ResponseWriter, r *http.Request) {
	var req DonateVideoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	viewer, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	videoID, err := uuid.Parse(req.VideoID)
	if err != nil && req.VideoID != "mock_vid_1" && req.VideoID != "mock_vid_2" {
		http.Error(w, "Invalid Video ID", http.StatusBadRequest)
		return
	}

	if req.VideoID == "mock_vid_1" {
		videoID = uuid.MustParse("00000000-0000-0000-0000-000000000011")
	} else if req.VideoID == "mock_vid_2" {
		videoID = uuid.MustParse("00000000-0000-0000-0000-000000000012")
	}

	var video models.VideoEmbed
	var channel models.Channel
	
	if req.VideoID == "mock_vid_1" || req.VideoID == "mock_vid_2" {
		video = models.VideoEmbed{
			ChannelID: viewer.ID, // Just use viewer as channel owner for mock
		}
		channel = models.Channel{
			OwnerID: viewer.ID,
		}
	} else {
		if err := database.DB.Where("id = ?", videoID).First(&video).Error; err != nil {
			http.Error(w, "Video not found", http.StatusNotFound)
			return
		}

		if err := database.DB.Where("id = ?", video.ChannelID).First(&channel).Error; err != nil {
			http.Error(w, "Channel not found", http.StatusNotFound)
			return
		}
	}

	// Prevent self-donating exploit
	if viewer.ID == channel.OwnerID {
		http.Error(w, "No puedes donar a tu propio video", http.StatusForbidden)
		return
	}

	// 1000 Esencias Azules = $1 USD
	usdEquivalent := req.Amount / 1000.0

	tx := database.DB.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	var buyerWallet models.Wallet
	if err := tx.Where("user_id = ?", viewer.ID).First(&buyerWallet).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Viewer wallet not found", http.StatusBadRequest)
		return
	}
	if req.Amount <= 0 {
		tx.Rollback()
		http.Error(w, "Invalid donation amount", http.StatusBadRequest)
		return
	}
	if buyerWallet.BalanceEssence < req.Amount {
		tx.Rollback()
		http.Error(w, "Insufficient Esencia Azul", http.StatusPaymentRequired)
		return
	}
	
	// Atomic update for buyer
	result := tx.Model(&buyerWallet).Where("balance_essence >= ?", req.Amount).UpdateColumn("balance_essence", gorm.Expr("balance_essence - ?", req.Amount))
	if result.Error != nil || result.RowsAffected == 0 {
		tx.Rollback()
		http.Error(w, "Saldo insuficiente o error de base de datos", http.StatusPaymentRequired)
		return
	}

	// Update creator
	var creatorWallet models.Wallet
	if err := tx.Where("user_id = ?", channel.OwnerID).First(&creatorWallet).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			creatorWallet = models.Wallet{UserID: channel.OwnerID, BalanceUSD: usdEquivalent}
			if err := tx.Create(&creatorWallet).Error; err != nil {
				tx.Rollback()
				http.Error(w, "Database error", http.StatusInternalServerError)
				return
			}
		} else {
			tx.Rollback()
			http.Error(w, "Database error", http.StatusInternalServerError)
			return
		}
	} else {
		if err := tx.Model(&creatorWallet).UpdateColumn("balance_usd", gorm.Expr("balance_usd + ?", usdEquivalent)).Error; err != nil {
			tx.Rollback()
			http.Error(w, "Database error", http.StatusInternalServerError)
			return
		}
	}

	txRec := models.Transaction{
		UserID:          channel.OwnerID,
		Type:            "donation",
		AmountUSD:       usdEquivalent,
		AmountEssence:   req.Amount,
		RelatedEntityID: &videoID,
		Status:          "completed",
	}
	if err := tx.Create(&txRec).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	
	if err := tx.Commit().Error; err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
}

func GetFinancialDashboard(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var wallet models.Wallet
	database.DB.Where("user_id = ?", user.ID).FirstOrCreate(&wallet, models.Wallet{UserID: user.ID})

	var transactions []models.Transaction
	database.DB.Where("user_id = ? AND type = 'donation'", user.ID).Order("created_at asc").Find(&transactions)

	thirtyDaysAgo := time.Now().AddDate(0, 0, -30)
	var earned30Days float64
	database.DB.Model(&models.Transaction{}).
		Where("user_id = ? AND type IN ? AND created_at <= ?", user.ID, []string{"donation", "purchase_fanart", "subscription_payout"}, thirtyDaysAgo).
		Select("COALESCE(SUM(amount_usd), 0)").Scan(&earned30Days)
	
	var totalWithdrawn float64
	database.DB.Model(&models.Transaction{}).
		Where("user_id = ? AND type = ?", user.ID, "payout").
		Select("COALESCE(SUM(amount_usd), 0)").Scan(&totalWithdrawn)
	
	withdrawableUsd := earned30Days - totalWithdrawn
	if withdrawableUsd < 0 {
		withdrawableUsd = 0
	}

	limit := 100.0
	if user.Role == "entrepreneur" {
		limit = 1000.0
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"total_usd":        wallet.BalanceUSD,
		"total_essences":      wallet.BalanceEssence,
		"withdrawable_usd": withdrawableUsd,
		"withdrawal_limit": limit,
		"role":             user.Role,
		"transactions":     transactions,
	})
}

func WithdrawFunds(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	tx := database.DB.Begin()

	var wallet models.Wallet
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("user_id = ?", user.ID).First(&wallet).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Wallet not found", http.StatusNotFound)
		return
	}

	limit := 100.0
	if user.Role == "entrepreneur" {
		limit = 1000.0
		
		// Enforce escrow/retention clause (Point 5)
		if user.SubscriptionEndsAt == nil || time.Now().After(*user.SubscriptionEndsAt) {
			tx.Rollback()
			http.Error(w, "Tu suscripción de emprendedor ha expirado. Renueva tu plan para poder retirar tus fondos.", http.StatusPaymentRequired)
			return
		}
	}

	thirtyDaysAgo := time.Now().AddDate(0, 0, -30)
	var earned30Days float64
	tx.Model(&models.Transaction{}).
		Where("user_id = ? AND type IN ? AND created_at <= ?", user.ID, []string{"donation", "purchase_fanart", "subscription_payout"}, thirtyDaysAgo).
		Select("COALESCE(SUM(amount_usd), 0)").Scan(&earned30Days)
	
	var totalWithdrawn float64
	tx.Model(&models.Transaction{}).
		Where("user_id = ? AND type = ?", user.ID, "payout").
		Select("COALESCE(SUM(amount_usd), 0)").Scan(&totalWithdrawn)
	
	withdrawableUsd := earned30Days - totalWithdrawn

	if withdrawableUsd < limit {
		tx.Rollback()
		http.Error(w, "No alcanza el monto mínimo maduro (30 días) para retirar", http.StatusBadRequest)
		return
	}

	if user.StripeAccountID == nil || *user.StripeAccountID == "" {
		tx.Rollback()
		http.Error(w, "Debes vincular tu cuenta bancaria (Stripe) antes de retirar fondos.", http.StatusBadRequest)
		return
	}

	withdrawalFee := 2.0
	withdrawnAmount := withdrawableUsd - withdrawalFee
	
	// Deduct the full amount (including fee) from the user's wallet
	wallet.BalanceUSD -= withdrawableUsd
	
	if err := tx.Save(&wallet).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to update wallet", http.StatusInternalServerError)
		return
	}

	// ----------------------------------------------------
	// STRIPE TRANSFER (Payout to Connected Account)
	// ----------------------------------------------------
	if stripe.Key == "" {
		stripe.Key = os.Getenv("STRIPE_SECRET_KEY")
	}
	transferParams := &stripe.TransferParams{
		Amount:      stripe.Int64(int64(withdrawnAmount * 100)), // Convert to cents
		Currency:    stripe.String(string(stripe.CurrencyUSD)),
		Destination: stripe.String(*user.StripeAccountID),
		Description: stripe.String("Retiro de fondos desde Drafting"),
	}

	_, err := transfer.New(transferParams)
	var txStatus string
	if err != nil {
		// Log the error but record the transaction as failed so they can retry
		txStatus = "failed_payout"
		wallet.BalanceUSD += withdrawableUsd // refund the full amount
		tx.Save(&wallet)
	} else {
		txStatus = "completed"
	}
	// ----------------------------------------------------

	txRec := models.Transaction{
		UserID:    user.ID,
		Type:      "payout",
		AmountUSD: withdrawnAmount,
		Status:    txStatus,
	}
	if err := tx.Create(&txRec).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to create transaction", http.StatusInternalServerError)
		return
	}

	if txStatus == "failed_payout" {
		tx.Commit()
		http.Error(w, "Error procesando el pago en Stripe: "+err.Error(), http.StatusBadGateway)
		return
	}

	tx.Commit()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "withdrawn": withdrawnAmount})
}

// GetLeaderboard returns the top creators by USD earnings
func GetLeaderboard(w http.ResponseWriter, r *http.Request) {
	type LeaderboardEntry struct {
		Name     string  `json:"name"`
		Champion string  `json:"champion"`
		Earnings float64 `json:"earnings"`
		IsPro    bool    `json:"isPro"`
		IsPremium bool   `json:"isPremium"`
	}

	var results []LeaderboardEntry

	// Aggregate earnings from transactions joining Users and Channels
	query := `
		SELECT 
			COALESCE(c.name, split_part(u.email, '@', 1)) as name, 
			'Creador Principal' as champion, 
			COALESCE(SUM(t.amount_usd), 0) as earnings,
			COALESCE(c.verified, false) as is_pro,
			(u.role = 'entrepreneur') as is_premium
		FROM transactions t
		JOIN users u ON t.user_id = u.id
		LEFT JOIN channels c ON c.owner_id = u.id
		WHERE t.type IN ('donation', 'purchase_fanart', 'subscription_payout')
		  AND t.created_at >= date_trunc('month', CURRENT_DATE)
		GROUP BY u.id, u.email, c.name, c.verified, u.role
		ORDER BY earnings DESC
		LIMIT 10
	`
	database.DB.Raw(query).Scan(&results)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(results)
}


