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

func TestValidateStoreReceiptSecurity(t *testing.T) {
	// 1. Debe rechazar comprobantes vacíos (nunca autogenerar IDs que regalen consultas)
	if _, _, _, errMsg := handlers.ValidateStoreReceipt("google_play", "", ""); errMsg == "" {
		t.Errorf("Se esperaba error cuando txID y token están vacíos")
	}

	// 2. Debe rechazar proveedores sandbox o de prueba
	if _, _, _, errMsg := handlers.ValidateStoreReceipt("google_play_sandbox", "GPA.1234", "tok_123"); errMsg == "" {
		t.Errorf("Se esperaba rechazo para proveedor google_play_sandbox")
	}

	// 3. Debe rechazar IDs de transacción simulados (test_gp_...)
	if _, _, _, errMsg := handlers.ValidateStoreReceipt("google_play", "test_gp_123456", "tok_123"); errMsg == "" {
		t.Errorf("Se esperaba rechazo para txID simulado test_gp_...")
	}

	// 4. Si orderId viene vacío pero purchase_token existe, debe usar purchase_token como txID idempotente
	prov, txID, tok, errMsg := handlers.ValidateStoreReceipt("", "", "real_play_token_abc123")
	if errMsg != "" {
		t.Fatalf("No se esperaba error con purchase_token válido: %s", errMsg)
	}
	if prov != "google_play" || txID != "real_play_token_abc123" || tok != "real_play_token_abc123" {
		t.Errorf("Normalización inesperada: prov=%s, txID=%s, tok=%s", prov, txID, tok)
	}
}

func TestDonationTierResolutionAndEconomics(t *testing.T) {
	testCases := []struct {
		inputKey      string
		expectedID    string
		expectedPrice float64
		expectedBonus int
	}{
		{"donate_10", "donate_10", 0.10, 2},
		{"donate_25", "donate_25", 0.25, 5},
		{"donate_49", "donate_49", 0.49, 10},
		{"donate_75", "donate_75", 0.75, 15},
		{"donate_99", "donate_99", 0.99, 25},
	}

	for _, tc := range testCases {
		t.Run(tc.inputKey, func(t *testing.T) {
			tier, exists := handlers.ResolveDonationTier(tc.inputKey)
			if !exists {
				t.Fatalf("Expected donation tier %s to exist", tc.inputKey)
			}
			if tier.ID != tc.expectedID {
				t.Errorf("Expected tier ID %s, got %s", tc.expectedID, tier.ID)
			}
			if tier.PriceUSD != tc.expectedPrice {
				t.Errorf("Expected price %f, got %f", tc.expectedPrice, tier.PriceUSD)
			}
			if tier.BonusQueries != tc.expectedBonus {
				t.Errorf("Expected bonus queries %d, got %d", tc.expectedBonus, tier.BonusQueries)
			}
		})
	}
}
