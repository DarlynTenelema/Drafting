package models_test

import (
	"backend/internal/models"
	"testing"

	"github.com/google/uuid"
)

func TestUserQueryAccounting(t *testing.T) {
	user := models.User{
		ID:                  uuid.New(),
		BonusQueries:        10,
		DailyQueries:        3,
		AdQueries:           0,
		AvailableQueries:    13,
		LastDailyRewardDate: "2026-10-24",
	}

	// 1. Consume 3 daily queries first
	for i := 0; i < 3; i++ {
		ok := user.ConsumeQuery()
		if !ok {
			t.Fatalf("Expected ConsumeQuery to succeed at step %d", i)
		}
	}
	if user.DailyQueries != 0 {
		t.Errorf("Expected DailyQueries to be 0, got %d", user.DailyQueries)
	}
	if user.BonusQueries != 10 {
		t.Errorf("Expected BonusQueries to remain 10, got %d", user.BonusQueries)
	}
	if user.AvailableQueries != 10 {
		t.Errorf("Expected AvailableQueries to be 10, got %d", user.AvailableQueries)
	}

	// 2. Consume bonus queries next
	for i := 0; i < 5; i++ {
		user.ConsumeQuery()
	}
	if user.BonusQueries != 5 {
		t.Errorf("Expected BonusQueries to be 5, got %d", user.BonusQueries)
	}
	if user.AvailableQueries != 5 {
		t.Errorf("Expected AvailableQueries to be 5, got %d", user.AvailableQueries)
	}

	// 3. Add Ad/Referral Queries (+5)
	user.AddAdQueries(5)
	if user.AdQueries != 5 {
		t.Errorf("Expected AdQueries to be 5, got %d", user.AdQueries)
	}
	if user.AvailableQueries != 10 {
		t.Errorf("Expected AvailableQueries to be 10 (5 bonus + 5 ad), got %d", user.AvailableQueries)
	}

	// 4. Daily Refresh should hard cap at 3 (never stack beyond 3)
	refreshed := user.RefreshDailyQueries("2026-10-25")
	if !refreshed {
		t.Errorf("Expected RefreshDailyQueries to return true on new date")
	}
	if user.DailyQueries != 3 {
		t.Errorf("Expected DailyQueries to be strictly 3, got %d", user.DailyQueries)
	}
	if user.AvailableQueries != 13 {
		t.Errorf("Expected AvailableQueries to be 13 (3 daily + 5 bonus + 5 ad), got %d", user.AvailableQueries)
	}

	// 5. Calling Refresh again on same day should do nothing
	refreshedAgain := user.RefreshDailyQueries("2026-10-25")
	if refreshedAgain {
		t.Errorf("Expected RefreshDailyQueries to return false on same date")
	}
	if user.DailyQueries != 3 {
		t.Errorf("Expected DailyQueries to remain 3, got %d", user.DailyQueries)
	}
}

func TestReferralCodeGeneration(t *testing.T) {
	id := uuid.MustParse("1f497722-3d69-4c89-8410-5c7f489d67dc")
	code := models.GenerateReferralCode(id)

	if code == "" {
		t.Fatalf("Expected non-empty referral code")
	}
	if len(code) < 4 {
		t.Fatalf("Referral code too short: %s", code)
	}
	if code[:2] != "WR" {
		t.Fatalf("Expected referral code to start with 'WR', got %s", code)
	}
}
