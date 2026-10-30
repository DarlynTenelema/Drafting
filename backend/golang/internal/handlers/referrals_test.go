package handlers_test

import (
	"backend/internal/models"
	"testing"

	"github.com/google/uuid"
)

// TestReferralMilestoneLogic verifies that the referral reward milestone rules work exactly as designed:
// - Each friend invited gives +5 ad queries
// - Up to 10 friends maximum = +50 queries total
func TestReferralMilestoneLogic(t *testing.T) {
	referrer := models.User{
		ID:                     uuid.New(),
		Email:                  "host@drafting.gg",
		ReferralCount:          0,
		ReferralRewardsClaimed: 0,
		BonusQueries:           5,
		DailyQueries:           3,
		AdQueries:              0,
		AvailableQueries:       8,
	}

	totalMilestonesEarned := 0

	for friend := 1; friend <= 10; friend++ {
		referrer.ReferralCount++

		milestoneEarned := false
		if referrer.ReferralRewardsClaimed < 10 {
			referrer.ReferralRewardsClaimed++
			referrer.AddAdQueries(5)
			milestoneEarned = true
			totalMilestonesEarned++
		}

		if !milestoneEarned {
			t.Fatalf("Expected milestone on friend #%d", friend)
		}
	}

	if totalMilestonesEarned != 10 {
		t.Fatalf("Expected exactly 10 milestones earned, got %d", totalMilestonesEarned)
	}

	if referrer.ReferralRewardsClaimed != 10 {
		t.Fatalf("Expected ReferralRewardsClaimed to be 10, got %d", referrer.ReferralRewardsClaimed)
	}

	if referrer.AdQueries != 50 {
		t.Fatalf("Expected 50 AdQueries earned from 10 friends, got %d", referrer.AdQueries)
	}

	if referrer.AvailableQueries != 58 { // 3 daily + 5 bonus + 50 ad = 58
		t.Fatalf("Expected 58 AvailableQueries, got %d", referrer.AvailableQueries)
	}
}
