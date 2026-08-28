package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"backend/internal/config"
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

func getCoinsForProduct(productID string) float64 {
	switch productID {
	case "coin_pack_1":
		return 100.00 // $1 USD pack = 100 GoldenCoins
	case "coin_pack_5":
		return 550.00 // $5 USD pack = 550 GoldenCoins
	case "coin_pack_10":
		return 1200.00 // $10 USD pack = 1200 GoldenCoins
	case "coin_pack_20":
		return 2500.00 // $20 USD pack = 2500 GoldenCoins
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

	// Record Transaction
	transaction := models.Transaction{
		UserID:     user.ID,
		Type:       "recharge_coin",
		AmountCoin: coinsToAdd,
		Status:     purchaseToken, // Using status for idempotency temporarily
	}
	if err := tx.Create(&transaction).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to record transaction", http.StatusInternalServerError)
		return
	}

	tx.Commit()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":     true,
		"new_balance": wallet.BalanceCoin,
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

	// Fetch Group to calculate splits
	var group models.Group
	if err := database.DB.Where("id = ?", groupID).First(&group).Error; err != nil {
		http.Error(w, "Group not found", http.StatusNotFound)
		return
	}

	// Verify the subscription purchase
	if playStoreVerifier != nil && playStoreVerifier.Enabled() {
		if err := playStoreVerifier.VerifySubscriptionPurchase(r.Context(), req.PurchaseToken); err != nil {
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

	// 4. Gemini API Cost deduction (Dynamic 10% of gross)
	apiCost := gross * 0.10
	finalEntrepreneurPayout := entrepreneurShare - apiCost

	tx := database.DB.Begin()

	// Update Entrepreneur's USD Wallet
	var entWallet models.Wallet
	if err := tx.Where("user_id = ?", group.OwnerID).First(&entWallet).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			entWallet = models.Wallet{UserID: group.OwnerID}
			tx.Create(&entWallet)
		}
	}
	entWallet.BalanceUSD += finalEntrepreneurPayout
	tx.Save(&entWallet)

	// Update App's internal ledger (optional, we keep our share intact)
	_ = appShare 

	// Record Transaction
	transaction := models.Transaction{
		UserID:    group.OwnerID,
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
		RelatedEntityID: &groupID,
		Status:          "completed",
	}
	tx.Create(&buyerTx)

	// Record the active subscription linking the user to the GroupID.
	user.ActiveGroupID = &groupID
	if err := tx.Save(user).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to link user to group", http.StatusInternalServerError)
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

	// Fetch OTPProfile to find owner
	var profile models.OTPProfile
	if err := database.DB.Where("id = ?", profileID).First(&profile).Error; err != nil {
		http.Error(w, "Creator profile not found", http.StatusNotFound)
		return
	}

	// Verify the subscription purchase
	if playStoreVerifier != nil && playStoreVerifier.Enabled() {
		if err := playStoreVerifier.VerifySubscriptionPurchase(r.Context(), req.PurchaseToken); err != nil {
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
	apiCost := gross * 0.10
	finalEntrepreneurPayout := entrepreneurShare - apiCost

	tx := database.DB.Begin()

	var entWallet models.Wallet
	if err := tx.Where("user_id = ?", profile.OwnerID).First(&entWallet).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			entWallet = models.Wallet{UserID: profile.OwnerID}
			tx.Create(&entWallet)
		}
	}
	entWallet.BalanceUSD += finalEntrepreneurPayout
	tx.Save(&entWallet)

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
	}
	tx.Create(&buyerTx)

	tx.Commit()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":    true,
		"message":    "Subscribed to creator successfully.",
		"creator_id": profileID,
	})
}

type SubmitCustomCoinRequest struct {
	Name     string  `json:"name"`
	USDValue float64 `json:"usd_value"`
	ImageURL string  `json:"image_url"`
}

// SubmitCustomCoin allows creating a custom 3D wrapped coin, pending admin approval
func SubmitCustomCoin(w http.ResponseWriter, r *http.Request) {
	var req SubmitCustomCoinRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	coin := models.CustomCoin{
		CreatorID: user.ID,
		Name:      req.Name,
		USDValue:  req.USDValue,
		ImageURL:  req.ImageURL,
		Status:    "pending",
	}

	if err := database.DB.Create(&coin).Error; err != nil {
		http.Error(w, "Failed to create coin", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(coin)
}

type PurchaseFanartRequest struct {
	FanartID string `json:"fanart_id"`
}

// PurchaseFanart deducts GoldenCoins from buyer and credits USD to creator
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
	if err != nil {
		http.Error(w, "Invalid Fanart ID", http.StatusBadRequest)
		return
	}

	var fanart models.Fanart
	if err := database.DB.Where("id = ? AND status = ?", fanartID, "approved").First(&fanart).Error; err != nil {
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

	if buyerWallet.BalanceCoin < fanart.PriceCoin {
		tx.Rollback()
		http.Error(w, "Insufficient GoldenCoins", http.StatusPaymentRequired)
		return
	}

	var creatorWallet models.Wallet
	if err := tx.Where("user_id = ?", fanart.CreatorID).First(&creatorWallet).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			creatorWallet = models.Wallet{UserID: fanart.CreatorID}
			tx.Create(&creatorWallet)
		}
	}

	// Calculate equivalent USD (100 GoldenCoins = $1 USD)
	// Creator takes 50% of the real USD value
	usdEarned := (fanart.PriceCoin / 100.0) * 0.50

	// Deduct from buyer
	buyerWallet.BalanceCoin -= fanart.PriceCoin
	tx.Save(&buyerWallet)

	// Add to creator
	creatorWallet.BalanceUSD += usdEarned
	tx.Save(&creatorWallet)

	// Record Transaction
	txRec := models.Transaction{
		UserID:          buyer.ID,
		Type:            "purchase_fanart",
		AmountCoin:      fanart.PriceCoin,
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

	fanartID, err := uuid.Parse(fanartIDStr)
	if err != nil {
		http.Error(w, "Invalid Fanart ID", http.StatusBadRequest)
		return
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
	if err != nil {
		http.Error(w, "Invalid Video ID", http.StatusBadRequest)
		return
	}

	var video models.VideoEmbed
	if err := database.DB.Where("id = ?", videoID).First(&video).Error; err != nil {
		http.Error(w, "Video not found", http.StatusNotFound)
		return
	}

	var channel models.Channel
	if err := database.DB.Where("id = ?", video.ChannelID).First(&channel).Error; err != nil {
		http.Error(w, "Channel not found", http.StatusNotFound)
		return
	}

	// 100 Esencias Azules = $1 USD
	usdEquivalent := req.Amount / 100.0

	tx := database.DB.Begin()

	if !isTestAccount(viewer.Email) {
		var buyerWallet models.Wallet
		if err := tx.Where("user_id = ?", viewer.ID).First(&buyerWallet).Error; err != nil {
			tx.Rollback()
			http.Error(w, "Viewer wallet not found", http.StatusBadRequest)
			return
		}
		if buyerWallet.BalanceCoin < req.Amount {
			tx.Rollback()
			http.Error(w, "Insufficient Esencia Azul", http.StatusPaymentRequired)
			return
		}
		buyerWallet.BalanceCoin -= req.Amount
		tx.Save(&buyerWallet)
	}

	var creatorWallet models.Wallet
	if err := tx.Where("user_id = ?", channel.OwnerID).First(&creatorWallet).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			creatorWallet = models.Wallet{UserID: channel.OwnerID}
			tx.Create(&creatorWallet)
		} else {
			tx.Rollback()
			http.Error(w, "Database error", http.StatusInternalServerError)
			return
		}
	}
	creatorWallet.BalanceUSD += usdEquivalent
	tx.Save(&creatorWallet)

	txRec := models.Transaction{
		UserID:          channel.OwnerID, // We record this on the creator's ledger for dashboard
		Type:            "donation",
		AmountUSD:       usdEquivalent,
		AmountCoin:      req.Amount,
		RelatedEntityID: &videoID,
		Status:          "completed",
	}
	tx.Create(&txRec)
	tx.Commit()

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
		"total_coins":      wallet.BalanceCoin,
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
	if err := tx.Where("user_id = ?", user.ID).First(&wallet).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Wallet not found", http.StatusNotFound)
		return
	}

	limit := 100.0
	if user.Role == "entrepreneur" {
		limit = 1000.0
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

	withdrawnAmount := withdrawableUsd
	wallet.BalanceUSD -= withdrawnAmount
	
	if err := tx.Save(&wallet).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to update wallet", http.StatusInternalServerError)
		return
	}

	txRec := models.Transaction{
		UserID:    user.ID,
		Type:      "payout",
		AmountUSD: withdrawnAmount,
		Status:    "pending_payout",
	}
	if err := tx.Create(&txRec).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to create transaction", http.StatusInternalServerError)
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

// GetPendingCustomCoins returns a list of custom coins awaiting approval
func GetPendingCustomCoins(w http.ResponseWriter, r *http.Request) {
	var coins []models.CustomCoin
	database.DB.Where("status = ?", "pending").Find(&coins)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(coins)
}

// ReviewCustomCoin handles approve or reject actions on pending custom coins.
func ReviewCustomCoin(w http.ResponseWriter, r *http.Request) {
	type ReviewRequest struct {
		CoinID string `json:"coin_id"`
		Status string `json:"status"` // "approved" or "rejected"
	}
	var req ReviewRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if req.Status != "approved" && req.Status != "rejected" {
		http.Error(w, "Invalid status", http.StatusBadRequest)
		return
	}

	result := database.DB.Model(&models.CustomCoin{}).Where("id = ?", req.CoinID).Update("status", req.Status)
	if result.Error != nil {
		http.Error(w, "Failed to update coin", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
}

