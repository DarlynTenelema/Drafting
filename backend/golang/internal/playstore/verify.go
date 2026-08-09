package playstore

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"

	"backend/internal/config"

	androidpublisher "google.golang.org/api/androidpublisher/v3"
	"google.golang.org/api/option"
)

var ErrVerificationDisabled = errors.New("google play verification is disabled")

type Verifier struct {
	service     *androidpublisher.Service
	packageName string
	enabled     bool
}

func NewVerifier() (*Verifier, error) {
	enabled := strings.EqualFold(config.GetEnv("GOOGLE_PLAY_VERIFICATION_ENABLED", "false"), "true")
	if !enabled {
		return &Verifier{enabled: false}, nil
	}

	packageName := strings.TrimSpace(config.GetEnv("GOOGLE_PLAY_PACKAGE_NAME", ""))
	if packageName == "" {
		return nil, fmt.Errorf("GOOGLE_PLAY_PACKAGE_NAME is required when verification is enabled")
	}

	credentialsJSON := strings.TrimSpace(config.GetEnv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", ""))
	if credentialsJSON == "" {
		return nil, fmt.Errorf("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is required when verification is enabled")
	}

	ctx := context.Background()
	service, err := androidpublisher.NewService(ctx, option.WithCredentialsJSON([]byte(credentialsJSON)))
	if err != nil {
		return nil, fmt.Errorf("failed to create android publisher client: %w", err)
	}

	return &Verifier{
		service:     service,
		packageName: packageName,
		enabled:     true,
	}, nil
}

func (v *Verifier) Enabled() bool {
	return v.enabled
}

// VerifyProductPurchase validates a one-time in-app product purchase token.
func (v *Verifier) VerifyProductPurchase(ctx context.Context, productID, purchaseToken string) error {
	if !v.enabled {
		return ErrVerificationDisabled
	}

	purchase, err := v.service.Purchases.Products.Get(v.packageName, productID, purchaseToken).Context(ctx).Do()
	if err != nil {
		return fmt.Errorf("google play verification failed: %w", err)
	}

	// 0 = purchased, 1 = canceled, 2 = pending
	if purchase.PurchaseState != 0 {
		return fmt.Errorf("purchase is not completed (state=%d)", purchase.PurchaseState)
	}

	return nil
}
