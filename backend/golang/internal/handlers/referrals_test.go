package handlers_test

import (
	"backend/internal/models"
	"testing"

	"github.com/google/uuid"
)

// TestReferralMilestoneLogic verifies that the referral reward milestone rules work exactly as designed:
// - Every 2 friends invited gives +5 ad queries (unlimited/stacked)
// - Can be earned up to 5 times (10 friends maximum = +25 queries total)
func TestReferralMilestoneLogic(t *testing.T) {
	referrer := models.User{
		ID:                     uuid.New(),
		Email:                  "host@drafting.gg",
		ReferralCount:          0,
		ReferralRewardsClaimed: 0,
		BonusQueries:           10,
		DailyQueries:           3,
		AdQueries:              0,
		AvailableQueries:       13,
	}

	totalMilestonesEarned := 0

	for friend := 1; friend <= 10; friend++ {
		referrer.ReferralCount++

		milestoneEarned := false
		if referrer.ReferralCount/2 > referrer.ReferralRewardsClaimed && referrer.ReferralRewardsClaimed < 5 {
			referrer.ReferralRewardsClaimed++
			referrer.AddAdQueries(5)
			milestoneEarned = true
			totalMilestonesEarned++
		}

		if friend%2 == 0 {
			if !milestoneEarned {
				t.Fatalf("Expected milestone on friend #%d", friend)
			}
		} else {
			if milestoneEarned {
				t.Fatalf("Did not expect milestone on friend #%d (odd friend)", friend)
			}
		}
	}

	if totalMilestonesEarned != 5 {
		t.Fatalf("Expected exactly 5 milestones earned, got %d", totalMilestonesEarned)
	}

	if referrer.ReferralRewardsClaimed != 5 {
		t.Fatalf("Expected ReferralRewardsClaimed to be 5, got %d", referrer.ReferralRewardsClaimed)
	}

	if referrer.AdQueries != 25 {
		t.Fatalf("Expected 25 AdQueries earned from 10 friends, got %d", referrer.AdQueries)
	}

	if referrer.AvailableQueries != 38 { // 3 daily + 10 bonus + 25 ad = 38
		t.Fatalf("Expected 38 AvailableQueries, got %d", referrer.AvailableQueries)
	}
}
