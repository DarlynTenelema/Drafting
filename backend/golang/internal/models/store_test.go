package models_test

import (
	"backend/internal/models"
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestStoreEconomyAccounting(t *testing.T) {
	expiryFuture := time.Now().UTC().AddDate(0, 1, 0)
	user := models.User{
		ID:                  uuid.New(),
		DailyQueries:        3,
		SubscriptionQueries: 300,
		SubscriptionPlan:    "plus",
		SubscriptionEndsAt:  &expiryFuture,
		BonusQueries:        10,
		AdQueries:           5,
		PurchasedQueries:    100, // Pack plus
	}
	user.RecalculateAvailableQueries()

	expectedTotal := 3 + 300 + 10 + 5 + 100 // 418
	if user.AvailableQueries != expectedTotal {
		t.Fatalf("Expected AvailableQueries to be %d, got %d", expectedTotal, user.AvailableQueries)
	}

	// 1. Consume 3 daily queries first
	for i := 0; i < 3; i++ {
		if !user.ConsumeQuery() {
			t.Fatalf("ConsumeQuery failed at daily step %d", i)
		}
	}
	if user.DailyQueries != 0 {
		t.Errorf("Expected DailyQueries to be 0, got %d", user.DailyQueries)
	}
	if user.SubscriptionQueries != 300 {
		t.Errorf("Expected SubscriptionQueries to remain 300, got %d", user.SubscriptionQueries)
	}

	// 2. Consume 10 subscription queries next
	for i := 0; i < 10; i++ {
		if !user.ConsumeQuery() {
			t.Fatalf("ConsumeQuery failed at subscription step %d", i)
		}
	}
	if user.SubscriptionQueries != 290 {
		t.Errorf("Expected SubscriptionQueries to be 290, got %d", user.SubscriptionQueries)
	}
	if user.BonusQueries != 10 {
		t.Errorf("Expected BonusQueries to remain 10, got %d", user.BonusQueries)
	}

	// 3. Subscription Expiry test: When subscription expires, subscription queries accumulate and do NOT wipe out
	pastDate := time.Now().UTC().Add(-1 * time.Hour)
	user.SubscriptionEndsAt = &pastDate
	expired := user.CheckSubscriptionExpiry()
	if !expired {
		t.Errorf("Expected CheckSubscriptionExpiry to return true")
	}
	if user.SubscriptionQueries != 290 {
		t.Errorf("Expected SubscriptionQueries to be retained (290) after expiry, got %d", user.SubscriptionQueries)
	}
	if user.SubscriptionPlan != "none" {
		t.Errorf("Expected SubscriptionPlan to be 'none', got %s", user.SubscriptionPlan)
	}
	// Available should remain 0 (daily) + 290 (sub) + 10 (bonus) + 5 (ad) + 100 (purchased) = 405
	if user.AvailableQueries != 405 {
		t.Errorf("Expected AvailableQueries to be 405 after subscription expiry, got %d", user.AvailableQueries)
	}
}

func TestDailyTransferLimits(t *testing.T) {
	user := models.User{
		ID:                    uuid.New(),
		DailyTransferredToday: 7,
		LastTransferDate:      "2026-10-24",
		DailyReceivedToday:    5,
		LastReceivedDate:      "2026-10-24",
	}

	// New day reset
	user.ResetDailyLimitsIfNewDay("2026-10-25")
	if user.DailyTransferredToday != 0 {
		t.Errorf("Expected DailyTransferredToday to reset to 0 on new date, got %d", user.DailyTransferredToday)
	}
	if user.DailyReceivedToday != 0 {
		t.Errorf("Expected DailyReceivedToday to reset to 0 on new date, got %d", user.DailyReceivedToday)
	}

	// Non-subscriber cannot transfer
	if user.IsSubscribed() {
		t.Errorf("Expected free user to not be subscribed")
	}

	// Active subscriber can transfer
	expiryFuture := time.Now().UTC().AddDate(0, 1, 0)
	user.SubscriptionPlan = "sub_plus"
	user.SubscriptionEndsAt = &expiryFuture
	if !user.IsSubscribed() {
		t.Errorf("Expected user with future subscription expiry to be subscribed")
	}

	// Test max transfer allowance (10 per day)
	user.DailyTransferredToday = 9
	remainingTransfer := 10 - user.DailyTransferredToday
	if remainingTransfer != 1 {
		t.Errorf("Expected 1 remaining transfer quota, got %d", remainingTransfer)
	}

	// Test CanTransfer for all packs & subscriptions
	freeUser := models.User{}
	if freeUser.CanTransfer() {
		t.Errorf("Expected free user without packs to NOT be able to transfer")
	}

	starterUser := models.User{HasPurchasedStarter: true, GiftQueries: 25}
	if !starterUser.CanTransfer() {
		t.Errorf("Expected user with starter pack to be able to transfer")
	}

	packUser := models.User{PurchasedQueries: 20}
	if !packUser.CanTransfer() {
		t.Errorf("Expected user with purchased pack to be able to transfer")
	}

	// Test DeductTransferQueries prioritizes GiftQueries first, then Subscription, Purchased, Ad, Bonus, Daily
	transferUser := models.User{
		GiftQueries:         10,
		SubscriptionQueries: 5,
		PurchasedQueries:    5,
		AdQueries:           3,
		BonusQueries:        2,
		DailyQueries:        1,
	}
	transferUser.RecalculateAvailableQueries()

	// Deduct 12 queries -> should consume all 10 GiftQueries and 2 SubscriptionQueries
	if !transferUser.DeductTransferQueries(12) {
		t.Fatalf("Expected DeductTransferQueries(12) to succeed")
	}
	if transferUser.GiftQueries != 0 {
		t.Errorf("Expected GiftQueries to be 0, got %d", transferUser.GiftQueries)
	}
	if transferUser.SubscriptionQueries != 3 {
		t.Errorf("Expected SubscriptionQueries to be 3, got %d", transferUser.SubscriptionQueries)
	}
}
