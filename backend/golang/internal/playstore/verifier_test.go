package playstore_test

import (
	"context"
	"testing"

	"backend/internal/playstore"
)

func TestVerificationModeParsing(t *testing.T) {
	t.Setenv("GOOGLE_PLAY_VERIFICATION_ENABLED", "")
	if got := playstore.VerificationMode(); got != "off" {
		t.Fatalf("expected off, got %s", got)
	}

	t.Setenv("GOOGLE_PLAY_VERIFICATION_ENABLED", "audit")
	if got := playstore.VerificationMode(); got != "audit" {
		t.Fatalf("expected audit, got %s", got)
	}

	t.Setenv("GOOGLE_PLAY_VERIFICATION_ENABLED", "true")
	if got := playstore.VerificationMode(); got != "strict" {
		t.Fatalf("expected strict, got %s", got)
	}
}

func TestVerifyProductPurchaseModes(t *testing.T) {
	// En modo off no bloquea ni exige token
	t.Setenv("GOOGLE_PLAY_VERIFICATION_ENABLED", "false")
	if _, err := playstore.VerifyProductPurchase(context.Background(), "com.drafting.app", "pack_classic_100", ""); err != nil {
		t.Fatalf("expected no error when verification is off, got %v", err)
	}

	// En modo strict rechaza si falta purchase_token
	t.Setenv("GOOGLE_PLAY_VERIFICATION_ENABLED", "true")
	if _, err := playstore.VerifyProductPurchase(context.Background(), "com.drafting.app", "pack_classic_100", ""); err == nil {
		t.Fatalf("expected error in strict mode when purchase_token is empty")
	}

	// En modo audit no bloquea si falta purchase_token
	t.Setenv("GOOGLE_PLAY_VERIFICATION_ENABLED", "audit")
	if _, err := playstore.VerifyProductPurchase(context.Background(), "com.drafting.app", "pack_classic_100", ""); err != nil {
		t.Fatalf("expected audit mode not to block purchase, got %v", err)
	}
}
