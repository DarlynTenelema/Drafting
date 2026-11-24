package playstore

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"time"

	"backend/internal/config"

	"google.golang.org/api/androidpublisher/v3"
	"google.golang.org/api/option"
)

var (
	svcOnce sync.Once
	svcInst *androidpublisher.Service
	svcErr  error
)

// VerificationMode indica el modo de verificación de recibos de Google Play:
//   - "true" / "strict": valida contra Google Play Android Developer API y rechaza recibos inválidos.
//   - "audit": consulta Google Play y registra el resultado en logs sin bloquear compras (ideal para probar en producción antes de activar "true").
//   - "" / "false": desactivado (comportamiento legacy).
func VerificationMode() string {
	raw := strings.ToLower(strings.TrimSpace(config.GetEnv("GOOGLE_PLAY_VERIFICATION_ENABLED", "false")))
	switch raw {
	case "true", "strict", "1":
		return "strict"
	case "audit", "shadow", "log":
		return "audit"
	default:
		return "off"
	}
}

func getService(ctx context.Context) (*androidpublisher.Service, error) {
	svcOnce.Do(func() {
		saJSON := strings.TrimSpace(config.GetEnv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", ""))
		if saJSON == "" {
			svcErr = fmt.Errorf("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON no configurado")
			return
		}
		svcInst, svcErr = androidpublisher.NewService(
			ctx,
			option.WithCredentialsJSON([]byte(saJSON)),
			option.WithScopes(androidpublisher.AndroidpublisherScope),
		)
	})
	return svcInst, svcErr
}

// VerifyProductPurchase valida un producto consumible/in-app (packs, trivia, donaciones)
// contra Google Play Developer API. Devuelve el OrderId oficial de Google si está disponible.
func VerifyProductPurchase(ctx context.Context, packageName, productID, purchaseToken string) (string, error) {
	mode := VerificationMode()
	if mode == "off" {
		return "", nil
	}

	pkg := strings.TrimSpace(packageName)
	if pkg == "" {
		pkg = strings.TrimSpace(config.GetEnv("GOOGLE_PLAY_PACKAGE_NAME", "com.drafting.app"))
	}
	if strings.TrimSpace(purchaseToken) == "" {
		err := fmt.Errorf("purchase_token requerido para verificación con Google Play")
		if mode == "audit" {
			slog.Warn("[PlayVerify:AUDIT] Recibo sin purchase_token", "product_id", productID, "package", pkg)
			return "", nil
		}
		return "", err
	}

	verifyCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	svc, err := getService(verifyCtx)
	if err != nil {
		if mode == "audit" {
			slog.Warn("[PlayVerify:AUDIT] No se pudo inicializar cliente AndroidPublisher", "error", err)
			return "", nil
		}
		return "", fmt.Errorf("error inicializando verificación de Google Play: %w", err)
	}

	purchase, err := svc.Purchases.Products.Get(pkg, productID, purchaseToken).Context(verifyCtx).Do()
	if err != nil {
		if mode == "audit" {
			slog.Warn("[PlayVerify:AUDIT] Error consultando producto en Google Play",
				"product_id", productID, "package", pkg, "error", err)
			return "", nil
		}
		return "", fmt.Errorf("no se pudo verificar la compra en Google Play")
	}

	// PurchaseState: 0 = Purchased, 1 = Canceled, 2 = Pending
	if purchase.PurchaseState != 0 {
		if mode == "audit" {
			slog.Warn("[PlayVerify:AUDIT] Estado de compra no completado",
				"product_id", productID, "state", purchase.PurchaseState, "order_id", purchase.OrderId)
			return purchase.OrderId, nil
		}
		return "", fmt.Errorf("la compra no se encuentra completada en Google Play (estado=%d)", purchase.PurchaseState)
	}

	slog.Info("[PlayVerify] Compra verificada con Google Play",
		"mode", mode, "product_id", productID, "order_id", purchase.OrderId)
	return purchase.OrderId, nil
}

// VerifySubscriptionPurchase valida una suscripción contra Google Play Developer API.
func VerifySubscriptionPurchase(ctx context.Context, packageName, subscriptionID, purchaseToken string) (string, error) {
	mode := VerificationMode()
	if mode == "off" {
		return "", nil
	}

	pkg := strings.TrimSpace(packageName)
	if pkg == "" {
		pkg = strings.TrimSpace(config.GetEnv("GOOGLE_PLAY_PACKAGE_NAME", "com.drafting.app"))
	}
	if strings.TrimSpace(purchaseToken) == "" {
		err := fmt.Errorf("purchase_token requerido para verificación de suscripción con Google Play")
		if mode == "audit" {
			slog.Warn("[PlayVerify:AUDIT] Suscripción sin purchase_token", "subscription_id", subscriptionID, "package", pkg)
			return "", nil
		}
		return "", err
	}

	verifyCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	svc, err := getService(verifyCtx)
	if err != nil {
		if mode == "audit" {
			slog.Warn("[PlayVerify:AUDIT] No se pudo inicializar cliente AndroidPublisher", "error", err)
			return "", nil
		}
		return "", fmt.Errorf("error inicializando verificación de Google Play: %w", err)
	}

	sub, err := svc.Purchases.Subscriptionsv2.Get(pkg, purchaseToken).Context(verifyCtx).Do()
	if err != nil {
		if mode == "audit" {
			slog.Warn("[PlayVerify:AUDIT] Error consultando suscripción en Google Play",
				"subscription_id", subscriptionID, "package", pkg, "error", err)
			return "", nil
		}
		return "", fmt.Errorf("no se pudo verificar la suscripción en Google Play")
	}

	latestOrderID := ""
	if len(sub.LineItems) > 0 && sub.LineItems[0] != nil {
		latestOrderID = sub.LineItems[0].LatestSuccessfulOrderId
	}

	activeStates := sub.SubscriptionState == "SUBSCRIPTION_STATE_ACTIVE" ||
		sub.SubscriptionState == "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"
	if !activeStates {
		if mode == "audit" {
			slog.Warn("[PlayVerify:AUDIT] Suscripción no activa",
				"subscription_id", subscriptionID, "state", sub.SubscriptionState, "order_id", latestOrderID)
			return latestOrderID, nil
		}
		return "", fmt.Errorf("la suscripción no se encuentra activa en Google Play (estado=%s)", sub.SubscriptionState)
	}

	slog.Info("[PlayVerify] Suscripción verificada con Google Play",
		"mode", mode, "subscription_id", subscriptionID, "state", sub.SubscriptionState, "order_id", latestOrderID)
	return latestOrderID, nil
}
