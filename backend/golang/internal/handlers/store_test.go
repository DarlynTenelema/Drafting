package handlers_test

import (
	"backend/internal/handlers"
	"testing"
)

func TestPackResolutionAndEconomics(t *testing.T) {
	testCases := []struct {
		inputKey       string
		expectedID     string
		expectedPrice  float64
		expectedTotal  int
		expectedBonus  int
		isStarter      bool
	}{
		{"pack_starter", "pack_starter", 0.19, 50, 0, true},
		{"starter", "pack_starter", 0.19, 50, 0, true},
		{"pack_plus", "pack_plus", 0.19, 20, 0, false},
		{"plus", "pack_plus", 0.19, 20, 0, false},
		{"pack_pro", "pack_pro", 0.49, 50, 0, false},
		{"pro", "pack_pro", 0.49, 50, 0, false},
		{"pack_ultra", "pack_ultra", 0.99, 100, 0, false},
		{"ultra", "pack_ultra", 0.99, 100, 0, false},
	}

	for _, tc := range testCases {
		t.Run(tc.inputKey, func(t *testing.T) {
			pack, exists := handlers.ResolvePack(tc.inputKey)
			if !exists {
				t.Fatalf("Expected pack %s to exist", tc.inputKey)
			}
			if pack.ID != tc.expectedID {
				t.Errorf("Expected pack ID %s, got %s", tc.expectedID, pack.ID)
			}
			if pack.PriceUSD != tc.expectedPrice {
				t.Errorf("Expected price %f, got %f", tc.expectedPrice, pack.PriceUSD)
			}
			if pack.TotalQueries != tc.expectedTotal {
				t.Errorf("Expected total queries %d, got %d", tc.expectedTotal, pack.TotalQueries)
			}
			if pack.BonusQueries != tc.expectedBonus {
				t.Errorf("Expected bonus queries %d, got %d", tc.expectedBonus, pack.BonusQueries)
			}
			if pack.IsStarter != tc.isStarter {
				t.Errorf("Expected isStarter %v, got %v", tc.isStarter, pack.IsStarter)
			}
		})
	}
}

func TestSubscriptionResolutionAndEconomics(t *testing.T) {
	testCases := []struct {
		inputKey      string
		expectedID    string
		expectedPrice float64
		expectedMonth int
	}{
		{"sub_plus", "sub_plus", 0.99, 150},
		{"plus", "sub_plus", 0.99, 150},
		{"sub_pro", "sub_pro", 1.99, 300},
		{"pro", "sub_pro", 1.99, 300},
		{"sub_ultra", "sub_ultra", 2.99, 450},
		{"ultra", "sub_ultra", 2.99, 450},
	}

	for _, tc := range testCases {
		t.Run(tc.inputKey, func(t *testing.T) {
			sub, exists := handlers.ResolveSubscription(tc.inputKey)
			if !exists {
				t.Fatalf("Expected subscription %s to exist", tc.inputKey)
			}
			if sub.ID != tc.expectedID {
				t.Errorf("Expected subscription ID %s, got %s", tc.expectedID, sub.ID)
			}
			if sub.PriceUSD != tc.expectedPrice {
				t.Errorf("Expected price %f, got %f", tc.expectedPrice, sub.PriceUSD)
			}
			if sub.QueriesPerMonth != tc.expectedMonth {
				t.Errorf("Expected monthly queries %d, got %d", tc.expectedMonth, sub.QueriesPerMonth)
			}
		})
	}
}
