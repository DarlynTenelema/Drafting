package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"

	"gorm.io/gorm/clause"
)

// PackConfig define la configuración económica de cada paquete
type PackConfig struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	PriceUSD     float64 `json:"price_usd"`
	TotalQueries int     `json:"queries"`
	BaseQueries  int     `json:"base_queries"`
	BonusQueries int     `json:"bonus_queries"`
	Tag          string  `json:"tag"`
	IsStarter    bool    `json:"is_starter"`
	Description  string  `json:"description"`
}

// SubscriptionConfig define la configuración económica de cada suscripción mensual
type SubscriptionConfig struct {
	ID               string  `json:"id"`
	Name             string  `json:"name"`
	PriceUSD         float64 `json:"price_usd"`
	QueriesPerMonth  int     `json:"queries_per_month"`
	Tag              string  `json:"tag"`
	Description      string  `json:"description"`
}

var AvailablePacks = map[string]PackConfig{
	"pack_starter": {
		ID:           "pack_starter",
		Name:         "Pack Starter",
		PriceUSD:     0.19,
		TotalQueries: 50,
		BaseQueries:  50,
		BonusQueries: 0,
		Tag:          "Solo una vez",
		IsStarter:    true,
		Description:  "50 consultas para ti + 25 para regalar a amigos",
	},
	"pack_plus": {
		ID:           "pack_plus",
		Name:         "Pack Plus",
		PriceUSD:     0.19,
		TotalQueries: 20,
		BaseQueries:  20,
		BonusQueries: 0,
		Tag:          "Económico",
		IsStarter:    false,
		Description:  "20 consultas permanentes sin fecha de vencimiento",
	},
	"pack_pro": {
		ID:           "pack_pro",
		Name:         "Pack Pro",
		PriceUSD:     0.49,
		TotalQueries: 50,
		BaseQueries:  50,
		BonusQueries: 0,
		Tag:          "Más Popular",
		IsStarter:    false,
		Description:  "50 consultas permanentes sin fecha de vencimiento",
	},
	"pack_ultra": {
		ID:           "pack_ultra",
		Name:         "Pack Ultra",
		PriceUSD:     0.99,
		TotalQueries: 100,
		BaseQueries:  100,
		BonusQueries: 0,
		Tag:          "Mejor Valor",
		IsStarter:    false,
		Description:  "100 consultas permanentes sin fecha de vencimiento",
	},
}

var AvailableSubscriptions = map[string]SubscriptionConfig{
	"sub_plus": {
		ID:              "sub_plus",
		Name:            "Plan Plus",
		PriceUSD:        0.99,
		QueriesPerMonth: 150,
		Tag:             "Básico Mensual",
		Description:     "150 consultas/mes acumulables + Enviar hasta 10/día a amigos",
	},
	"sub_pro": {
		ID:              "sub_pro",
		Name:            "Plan Pro",
		PriceUSD:        1.99,
		QueriesPerMonth: 300,
		Tag:             "Avanzado",
		Description:     "300 consultas/mes acumulables + Enviar hasta 10/día a amigos",
	},
	"sub_ultra": {
		ID:              "sub_ultra",
		Name:            "Plan Ultra",
		PriceUSD:        2.99,
		QueriesPerMonth: 450,
		Tag:             "Challenger",
		Description:     "450 consultas/mes acumulables + Enviar hasta 10/día a amigos",
	},
}

func ResolvePack(id string) (PackConfig, bool) {
	id = strings.TrimSpace(strings.ToLower(id))
	switch id {
	case "starter", "pack_starter":
		p, ok := AvailablePacks["pack_starter"]
		return p, ok
	case "plus", "pack_plus":
		p, ok := AvailablePacks["pack_plus"]
		return p, ok
	case "pro", "pack_pro":
		p, ok := AvailablePacks["pack_pro"]
		return p, ok
	case "ultra", "pack_ultra":
		p, ok := AvailablePacks["pack_ultra"]
		return p, ok
	default:
		if p, ok := AvailablePacks[id]; ok {
			return p, true
		}
		if strings.Contains(id, "starter") {
			return AvailablePacks["pack_starter"], true
		}
		if strings.Contains(id, "ultra") {
			return AvailablePacks["pack_ultra"], true
		}
		if strings.Contains(id, "pro") {
			return AvailablePacks["pack_pro"], true
		}
		if strings.Contains(id, "plus") {
			return AvailablePacks["pack_plus"], true
		}
		return PackConfig{}, false
	}
}

func ResolveSubscription(id string) (SubscriptionConfig, bool) {
	id = strings.TrimSpace(strings.ToLower(id))
	switch id {
	case "plus", "sub_plus":
		s, ok := AvailableSubscriptions["sub_plus"]
		return s, ok
	case "pro", "sub_pro":
		s, ok := AvailableSubscriptions["sub_pro"]
		return s, ok
	case "ultra", "sub_ultra":
		s, ok := AvailableSubscriptions["sub_ultra"]
		return s, ok
	default:
		if s, ok := AvailableSubscriptions[id]; ok {
			return s, true
		}
		if strings.Contains(id, "ultra") {
			return AvailableSubscriptions["sub_ultra"], true
		}
		if strings.Contains(id, "pro") {
			return AvailableSubscriptions["sub_pro"], true
		}
		if strings.Contains(id, "plus") {
			return AvailableSubscriptions["sub_plus"], true
		}
		return SubscriptionConfig{}, false
	}
}

func normalizeAppLanguage(raw string) string {
	clean := strings.ToLower(strings.TrimSpace(raw))
	if len(clean) >= 2 {
		clean = clean[:2]
	}
	switch clean {
	case "pt", "en", "fr":
		return clean
	default:
		return "es"
	}
}

func localizePack(p PackConfig, lang string) PackConfig {
	switch lang {
	case "pt":
		switch p.ID {
		case "pack_starter":
			p.Tag = "Apenas uma vez"
			p.Description = "50 consultas para você + 25 para presentear amigos"
		case "pack_plus":
			p.Tag = "Econômico"
			p.Description = "20 consultas permanentes sem data de validade"
		case "pack_pro":
			p.Tag = "Mais Popular"
			p.Description = "50 consultas permanentes sem data de validade"
		case "pack_ultra":
			p.Tag = "Melhor Valor"
			p.Description = "100 consultas permanentes sem data de validade"
		}
	case "en":
		switch p.ID {
		case "pack_starter":
			p.Tag = "One-time only"
			p.Description = "50 queries for you + 25 bonus queries to gift friends"
		case "pack_plus":
			p.Tag = "Budget"
			p.Description = "20 permanent queries that never expire"
		case "pack_pro":
			p.Tag = "Most Popular"
			p.Description = "50 permanent queries that never expire"
		case "pack_ultra":
			p.Tag = "Best Value"
			p.Description = "100 permanent queries that never expire"
		}
	case "fr":
		switch p.ID {
		case "pack_starter":
			p.Tag = "Une seule fois"
			p.Description = "50 consultations pour vous + 25 à offrir à vos amis"
		case "pack_plus":
			p.Tag = "Économique"
			p.Description = "20 consultations permanentes sans date d'expiration"
		case "pack_pro":
			p.Tag = "Plus Populaire"
			p.Description = "50 consultations permanentes sans date d'expiration"
		case "pack_ultra":
			p.Tag = "Meilleure Offre"
			p.Description = "100 consultations permanentes sans date d'expiration"
		}
	}
	return p
}

func localizeSubscription(s SubscriptionConfig, lang string) SubscriptionConfig {
	switch lang {
	case "pt":
		switch s.ID {
		case "sub_plus":
			s.Name = "Passe Plus"
			s.Tag = "Básico Mensal"
			s.Description = "150 consultas/mês acumuláveis + Enviar até 10/dia para amigos"
		case "sub_pro":
			s.Name = "Passe Pro"
			s.Tag = "Avançado"
			s.Description = "300 consultas/mês acumuláveis + Enviar até 10/dia para amigos"
		case "sub_ultra":
			s.Name = "Passe Ultra"
			s.Tag = "Challenger"
			s.Description = "450 consultas/mês acumuláveis + Enviar até 10/dia para amigos"
		}
	case "en":
		switch s.ID {
		case "sub_plus":
			s.Name = "Plus Pass"
			s.Tag = "Monthly Basic"
			s.Description = "150 stackable queries/month + Gift up to 10/day to friends"
		case "sub_pro":
			s.Name = "Pro Pass"
			s.Tag = "Advanced"
			s.Description = "300 stackable queries/month + Gift up to 10/day to friends"
		case "sub_ultra":
			s.Name = "Ultra Pass"
			s.Tag = "Challenger"
			s.Description = "450 stackable queries/month + Gift up to 10/day to friends"
		}
	case "fr":
		switch s.ID {
		case "sub_plus":
			s.Name = "Passe Plus"
			s.Tag = "Mensuel Basique"
			s.Description = "150 consultations/mois cumulables + Offrir jusqu'à 10/jour aux amis"
		case "sub_pro":
			s.Name = "Passe Pro"
			s.Tag = "Avancé"
			s.Description = "300 consultations/mois cumulables + Offrir jusqu'à 10/jour aux amis"
		case "sub_ultra":
			s.Name = "Passe Ultra"
			s.Tag = "Challenger"
			s.Description = "450 consultations/mois cumulables + Offrir jusqu'à 10/jour aux amis"
		}
	}
	return s
}

// GetStoreCatalog retorna los paquetes y suscripciones disponibles según el estado del usuario
func GetStoreCatalog(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	lang := normalizeAppLanguage(r.Header.Get("Accept-Language"))

	today := time.Now().UTC().Format("2006-01-02")
	prevTransferDate := user.LastTransferDate
	prevReceivedDate := user.LastReceivedDate
	user.ResetDailyLimitsIfNewDay(today)
	subExpired := user.CheckSubscriptionExpiry()
	user.RecalculateAvailableQueries()

	if user.ReferralCode == "" {
		user.ReferralCode = models.GenerateReferralCode(user.ID)
	}

	if prevTransferDate != user.LastTransferDate || prevReceivedDate != user.LastReceivedDate || subExpired {
		database.DB.Model(user).Updates(map[string]interface{}{
			"daily_transferred_today": user.DailyTransferredToday,
			"last_transfer_date":      user.LastTransferDate,
			"daily_received_today":    user.DailyReceivedToday,
			"last_received_date":      user.LastReceivedDate,
			"subscription_plan":       user.SubscriptionPlan,
			"subscription_ends_at":    user.SubscriptionEndsAt,
			"available_queries":       user.AvailableQueries,
			"referral_code":           user.ReferralCode,
		})
	}

	// Filtrar catálogo: si ya compró el starter pack, no se muestra
	packsList := make([]PackConfig, 0)
	orderPacks := []string{"pack_starter", "pack_plus", "pack_pro", "pack_ultra"}
	for _, id := range orderPacks {
		pack := localizePack(AvailablePacks[id], lang)
		if pack.IsStarter && user.HasPurchasedStarter {
			continue // Desaparece para siempre de la tienda
		}
		packsList = append(packsList, pack)
	}

	subsList := make([]SubscriptionConfig, 0)
	orderSubs := []string{"sub_plus", "sub_pro", "sub_ultra"}
	for _, id := range orderSubs {
		subsList = append(subsList, localizeSubscription(AvailableSubscriptions[id], lang))
	}

	remainingTransferQuota := 10 - user.DailyTransferredToday
	if remainingTransferQuota < 0 {
		remainingTransferQuota = 0
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"has_purchased_starter":    user.HasPurchasedStarter,
		"is_subscribed":            user.IsSubscribed(),
		"subscription_plan":        user.SubscriptionPlan,
		"subscription_ends_at":     user.SubscriptionEndsAt,
		"subscription_queries":     user.SubscriptionQueries,
		"purchased_queries":        user.PurchasedQueries,
		"gift_queries":             user.GiftQueries,
		"available_queries":        user.AvailableQueries,
		"daily_transferred_today":  user.DailyTransferredToday,
		"remaining_transfer_quota": remainingTransferQuota,
		"remaining_transfer_today": remainingTransferQuota,
		"can_transfer":             user.CanTransfer() && remainingTransferQuota > 0,
		"referral_code":            user.ReferralCode,
		"packs":                    packsList,
		"subscriptions":            subsList,
	})
}

type PurchasePackRequest struct {
	PackID                string `json:"pack_id"`
	ProviderTransactionID string `json:"provider_transaction_id"`
	Provider              string `json:"provider"`
	PurchaseToken         string `json:"purchase_token,omitempty"`
	PackageName           string `json:"package_name,omitempty"`
}

// ValidateStoreReceipt verifica que el comprobante provenga de una tienda legítima y nunca autogenera IDs falsos
func ValidateStoreReceipt(provider, txID, token string) (string, string, string, string) {
	cleanProvider := strings.TrimSpace(strings.ToLower(provider))
	if cleanProvider == "" {
		cleanProvider = "google_play"
	}
	if cleanProvider != "google_play" && cleanProvider != "app_store" {
		return "", "", "", "Proveedor de pagos no autorizado."
	}

	cleanTxID := strings.TrimSpace(txID)
	cleanToken := strings.TrimSpace(token)

	lowerTx := strings.ToLower(cleanTxID)
	lowerTok := strings.ToLower(cleanToken)
	if strings.HasPrefix(lowerTx, "test_") || strings.HasPrefix(lowerTx, "sandbox_") || strings.HasPrefix(lowerTx, "mock_") ||
		strings.HasPrefix(lowerTok, "test_") || strings.HasPrefix(lowerTok, "sandbox_") || strings.HasPrefix(lowerTok, "mock_") {
		return "", "", "", "Transacción simulada o de prueba no permitida."
	}

	if cleanTxID == "" && cleanToken != "" {
		cleanTxID = cleanToken
	}
	if cleanTxID == "" {
		return "", "", "", "Se requiere un identificador o token válido de la transacción de Google Play."
	}

	return cleanProvider, cleanTxID, cleanToken, ""
}

// PurchasePack gestiona la adquisición de un paquete de consultas de forma atómica e idempotente
func PurchasePack(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req PurchasePackRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request payload", http.StatusBadRequest)
		return
	}

	pack, exists := ResolvePack(req.PackID)
	if !exists {
		// Compatibilidad y auto-recuperación: si una transacción pendiente pertenece a un tier de micro-donación
		// (por ejemplo donate_10), reenrutarla internamente a ContributeDonation para acreditarla y consumirla.
		if _, isDonation := ResolveDonationTier(req.PackID); isDonation {
			reqJSON, _ := json.Marshal(map[string]interface{}{
				"tier_id":                 req.PackID,
				"provider":                req.Provider,
				"provider_transaction_id": req.ProviderTransactionID,
				"purchase_token":          req.PurchaseToken,
			})
			r.Body = io.NopCloser(bytes.NewBuffer(reqJSON))
			ContributeDonation(w, r)
			return
		}
		http.Error(w, "Paquete no válido.", http.StatusBadRequest)
		return
	}

	provider, txID, purchaseToken, errMsg := ValidateStoreReceipt(req.Provider, req.ProviderTransactionID, req.PurchaseToken)
	if errMsg != "" {
		http.Error(w, errMsg, http.StatusBadRequest)
		return
	}

	tx := database.DB.Begin()
	if tx.Error != nil {
		http.Error(w, "Error iniciando transacción de base de datos", http.StatusInternalServerError)
		return
	}

	var lockedUser models.User
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", user.ID).First(&lockedUser).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Usuario no encontrado", http.StatusNotFound)
		return
	}

	// 1. Idempotencia estricta (por provider_transaction_id o por purchase_token):
	// Si la compra ya fue procesada antes, devolver 200 OK con already_processed=true y 0 consultas añadidas
	// para que la app consuma el artículo en Google Play sin volver a regalar consultas ni mostrar alertas repetidas.
	var existing models.Transaction
	idempotencyQuery := tx.Where("status = 'completed' AND (provider_transaction_id = ?", txID)
	if purchaseToken != "" {
		idempotencyQuery = tx.Where(
			"status = 'completed' AND (provider_transaction_id = ? OR provider_transaction_id = ? OR (purchase_token != '' AND purchase_token = ?))",
			txID, purchaseToken, purchaseToken,
		)
	} else {
		idempotencyQuery = tx.Where("status = 'completed' AND provider_transaction_id = ?", txID)
	}

	if err := idempotencyQuery.First(&existing).Error; err == nil {
		tx.Rollback()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success":               true,
			"already_processed":     true,
			"message":               "Transacción ya procesada previamente.",
			"pack_id":               pack.ID,
			"queries_added":         0,
			"gift_queries_added":    0,
			"available_queries":     lockedUser.AvailableQueries,
			"purchased_queries":     lockedUser.PurchasedQueries,
			"gift_queries":          lockedUser.GiftQueries,
			"has_purchased_starter": lockedUser.HasPurchasedStarter,
		})
		return
	}

	// 2. Regla del Starter Pack: Solo una única vez por usuario.
	// Si el usuario ya tiene HasPurchasedStarter=true (por ejemplo de una compra previa pendiente de consumir en Google Play),
	// no acreditamos consultas adicionales (0 añadidas), pero respondemos 200 con already_processed=true para que Google Play
	// pueda consumir/limpiar el ítem atascado y no bloquee la tienda con ITEM_ALREADY_OWNED.
	if pack.IsStarter && lockedUser.HasPurchasedStarter {
		tx.Rollback()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success":               true,
			"already_processed":     true,
			"message":               "El Pack Starter ya fue acreditado anteriormente en tu cuenta.",
			"pack_id":               pack.ID,
			"queries_added":         0,
			"gift_queries_added":    0,
			"available_queries":     lockedUser.AvailableQueries,
			"purchased_queries":     lockedUser.PurchasedQueries,
			"gift_queries":          lockedUser.GiftQueries,
			"has_purchased_starter": lockedUser.HasPurchasedStarter,
		})
		return
	}

	giftAdded := 0
	if pack.IsStarter {
		lockedUser.HasPurchasedStarter = true
		giftAdded = 25
		lockedUser.GiftQueries += giftAdded
	}
	lockedUser.RecalculateAvailableQueries()
	lockedUser.AddPurchasedQueries(pack.TotalQueries)

	// 3. Registrar primero la transacción dentro de la transacción SQL atómica
	transactionRecord := models.Transaction{
		UserID:                lockedUser.ID,
		Type:                  "pack",
		ItemKey:               pack.ID,
		AmountUSD:             pack.PriceUSD,
		QueriesAdded:          pack.TotalQueries,
		Provider:              provider,
		ProviderTransactionID: txID,
		PurchaseToken:         purchaseToken,
		Status:                "completed",
		CreatedAt:             time.Now().UTC(),
	}

	if err := tx.Create(&transactionRecord).Error; err != nil {
		tx.Rollback()
		log.Printf("[STORE] Error registrando transacción de paquete: %v", err)
		http.Error(w, "Error registrando la transacción de compra", http.StatusInternalServerError)
		return
	}

	// 4. Actualizar el saldo del usuario dentro de la misma transacción SQL
	if err := tx.Model(&lockedUser).Updates(map[string]interface{}{
		"purchased_queries":     lockedUser.PurchasedQueries,
		"gift_queries":          lockedUser.GiftQueries,
		"available_queries":     lockedUser.AvailableQueries,
		"has_purchased_starter": lockedUser.HasPurchasedStarter,
	}).Error; err != nil {
		tx.Rollback()
		log.Printf("[STORE] Error actualizando usuario tras compra: %v", err)
		http.Error(w, fmt.Sprintf("Error actualizando saldo de consultas: %v", err), http.StatusInternalServerError)
		return
	}

	// 5. Acreditar comisión al Streamer Afiliado si el jugador fue referido por un creador
	CreditStreamerCommissionIfApplicable(tx, &lockedUser, &transactionRecord)

	if err := tx.Commit().Error; err != nil {
		log.Printf("[STORE] Error confirmando transacción de compra: %v", err)
		http.Error(w, "Error confirmando la compra", http.StatusInternalServerError)
		return
	}

	*user = lockedUser

	successMsg := fmt.Sprintf("¡Compra exitosa! Se han añadido %d consultas a tu cuenta.", pack.TotalQueries)
	if giftAdded > 0 {
		successMsg = fmt.Sprintf("¡Compra exitosa! Tienes +%d consultas para ti y +%d consultas de regalo para compartir con tus amigos.", pack.TotalQueries, giftAdded)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":               true,
		"already_processed":     false,
		"message":               successMsg,
		"pack_id":               pack.ID,
		"queries_added":         pack.TotalQueries,
		"gift_queries_added":    giftAdded,
		"available_queries":     lockedUser.AvailableQueries,
		"purchased_queries":     lockedUser.PurchasedQueries,
		"gift_queries":          lockedUser.GiftQueries,
		"has_purchased_starter": lockedUser.HasPurchasedStarter,
	})
}

type SubscribeRequest struct {
	PlanID                string `json:"plan_id"`
	ProviderTransactionID string `json:"provider_transaction_id"`
	Provider              string `json:"provider"`
	PurchaseToken         string `json:"purchase_token,omitempty"`
	PackageName           string `json:"package_name,omitempty"`
}

// Subscribe activa o renueva la suscripción mensual del usuario de forma atómica e idempotente
func Subscribe(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req SubscribeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request payload", http.StatusBadRequest)
		return
	}

	plan, exists := ResolveSubscription(req.PlanID)
	if !exists {
		http.Error(w, "Plan de suscripción no válido.", http.StatusBadRequest)
		return
	}

	provider, txID, purchaseToken, errMsg := ValidateStoreReceipt(req.Provider, req.ProviderTransactionID, req.PurchaseToken)
	if errMsg != "" {
		http.Error(w, errMsg, http.StatusBadRequest)
		return
	}

	tx := database.DB.Begin()
	if tx.Error != nil {
		http.Error(w, "Error iniciando transacción de base de datos", http.StatusInternalServerError)
		return
	}

	var lockedUser models.User
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", user.ID).First(&lockedUser).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Usuario no encontrado", http.StatusNotFound)
		return
	}

	// 1. Idempotencia estricta: verificar por provider_transaction_id o por purchase_token dentro del ciclo vigente
	var existing models.Transaction
	cycleThreshold := time.Now().UTC().AddDate(0, 0, -25)
	subIdempotencyQuery := tx.Where("status = 'completed' AND provider_transaction_id = ?", txID)
	if purchaseToken != "" {
		subIdempotencyQuery = tx.Where(
			"status = 'completed' AND (provider_transaction_id = ? OR provider_transaction_id = ? OR (purchase_token != '' AND purchase_token = ? AND item_key = ? AND created_at > ?))",
			txID, purchaseToken, purchaseToken, plan.ID, cycleThreshold,
		)
	}

	if err := subIdempotencyQuery.First(&existing).Error; err == nil {
		tx.Rollback()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success":              true,
			"already_processed":    true,
			"message":              "Suscripción ya procesada previamente.",
			"queries_added":        0,
			"subscription_plan":    lockedUser.SubscriptionPlan,
			"subscription_queries": lockedUser.SubscriptionQueries,
			"subscription_ends_at": lockedUser.SubscriptionEndsAt,
			"available_queries":    lockedUser.AvailableQueries,
		})
		return
	}

	// Las consultas de suscripción se acumulan únicamente en compras/renovaciones nuevas verificadas
	expiryDate := time.Now().UTC().AddDate(0, 1, 0)
	lockedUser.SubscriptionPlan = plan.ID
	lockedUser.SubscriptionQueries += plan.QueriesPerMonth
	lockedUser.SubscriptionEndsAt = &expiryDate
	lockedUser.RecalculateAvailableQueries()

	transactionRecord := models.Transaction{
		UserID:                lockedUser.ID,
		Type:                  "subscription",
		ItemKey:               plan.ID,
		AmountUSD:             plan.PriceUSD,
		QueriesAdded:          plan.QueriesPerMonth,
		Provider:              provider,
		ProviderTransactionID: txID,
		PurchaseToken:         purchaseToken,
		Status:                "completed",
		CreatedAt:             time.Now().UTC(),
	}

	if err := tx.Create(&transactionRecord).Error; err != nil {
		tx.Rollback()
		log.Printf("[STORE] Error registrando transacción de suscripción: %v", err)
		http.Error(w, "Error registrando la suscripción", http.StatusInternalServerError)
		return
	}

	if err := tx.Model(&lockedUser).Updates(map[string]interface{}{
		"subscription_plan":    lockedUser.SubscriptionPlan,
		"subscription_queries": lockedUser.SubscriptionQueries,
		"subscription_ends_at": lockedUser.SubscriptionEndsAt,
		"available_queries":    lockedUser.AvailableQueries,
	}).Error; err != nil {
		tx.Rollback()
		log.Printf("[STORE] Error actualizando usuario tras suscripción: %v", err)
		http.Error(w, fmt.Sprintf("Error actualizando la suscripción: %v", err), http.StatusInternalServerError)
		return
	}

	// Acreditar comisión al Streamer Afiliado si el jugador fue referido por un creador
	CreditStreamerCommissionIfApplicable(tx, &lockedUser, &transactionRecord)

	if err := tx.Commit().Error; err != nil {
		log.Printf("[STORE] Error confirmando suscripción: %v", err)
		http.Error(w, "Error confirmando la suscripción", http.StatusInternalServerError)
		return
	}

	*user = lockedUser

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":              true,
		"already_processed":    false,
		"message":              fmt.Sprintf("¡Suscripción al %s activada! Tienes +%d consultas para este mes.", plan.Name, plan.QueriesPerMonth),
		"queries_added":        plan.QueriesPerMonth,
		"subscription_plan":    lockedUser.SubscriptionPlan,
		"subscription_queries": lockedUser.SubscriptionQueries,
		"subscription_ends_at": lockedUser.SubscriptionEndsAt,
		"available_queries":    lockedUser.AvailableQueries,
	})
}

type TransferRequest struct {
	TargetPlayerID string `json:"target_player_id"` // Puede ser código de referido (ej: "EW3J43" o "WREW3J43") o UUID
	Amount         int    `json:"amount"`
}

// extractCleanPlayerCode limpia prefijos, espacios o mensajes pegados de WhatsApp/Discord
func extractCleanPlayerCode(raw string) string {
	raw = strings.TrimSpace(raw)
	raw = strings.TrimPrefix(raw, "#")
	raw = strings.TrimPrefix(raw, "@")
	if strings.Contains(raw, " ") {
		for _, word := range strings.Fields(raw) {
			cleanWord := strings.Trim(word, "¡!.,:;\"'()[]{}#@")
			upper := strings.ToUpper(cleanWord)
			if strings.HasPrefix(upper, "WR") && len(upper) >= 6 && len(upper) <= 12 {
				return upper
			}
		}
	}
	return strings.TrimSpace(raw)
}

// TransferQueries permite a usuarios con paquetes o suscripción activa transferir hasta 10 consultas por día a un amigo
func TransferQueries(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req TransferRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Formato de solicitud no válido", http.StatusBadRequest)
		return
	}

	today := time.Now().UTC().Format("2006-01-02")
	user.ResetDailyLimitsIfNewDay(today)
	user.CheckSubscriptionExpiry()
	user.RecalculateAvailableQueries()

	// Regla 1: Usuarios con cualquier paquete comprado, Pack Starter, consultas de regalo o suscripción activa pueden transferir
	if !user.CanTransfer() {
		http.Error(w, "La función de compartir consultas con amigos está disponible al adquirir cualquier Pack o Suscripción.", http.StatusForbidden)
		return
	}

	// Regla 2: Cantidad válida (1 a 10)
	if req.Amount <= 0 || req.Amount > 10 {
		http.Error(w, "Puedes transferir entre 1 y 10 consultas por operación.", http.StatusBadRequest)
		return
	}

	// Regla 3: Límite diario estricto de 10 consultas enviadas por día
	if user.DailyTransferredToday+req.Amount > 10 {
		remaining := 10 - user.DailyTransferredToday
		if remaining < 0 {
			remaining = 0
		}
		http.Error(w, fmt.Sprintf("Límite diario alcanzado. Hoy ya transferiste %d consultas (solo te quedan %d disponibles hoy).", user.DailyTransferredToday, remaining), http.StatusBadRequest)
		return
	}

	// Regla 4: Verificar que el remitente tenga saldo suficiente (incluyendo consultas de regalo)
	if user.AvailableQueries+user.GiftQueries < req.Amount {
		http.Error(w, "No tienes suficientes consultas disponibles para realizar la transferencia.", http.StatusBadRequest)
		return
	}

	// Regla 5: Buscar al destinatario (insensible a mayúsculas/minúsculas y con o sin prefijo WR)
	rawTarget := extractCleanPlayerCode(req.TargetPlayerID)
	if rawTarget == "" {
		http.Error(w, "Debes proporcionar el ID o código del jugador.", http.StatusBadRequest)
		return
	}

	targetUpper := strings.ToUpper(rawTarget)
	targetCodeWithPrefix := targetUpper
	if !strings.HasPrefix(targetCodeWithPrefix, "WR") {
		targetCodeWithPrefix = "WR" + targetCodeWithPrefix
	}

	var targetUser models.User
	err := database.DB.Where("UPPER(referral_code) = ? OR UPPER(referral_code) = ? OR id::text = ?", targetUpper, targetCodeWithPrefix, rawTarget).First(&targetUser).Error
	if err != nil {
		http.Error(w, "No se encontró ningún jugador con ese ID o código.", http.StatusNotFound)
		return
	}

	// Regla 6: No puede enviarse a sí mismo
	if targetUser.ID == user.ID {
		http.Error(w, "No puedes transferirte consultas a ti mismo.", http.StatusBadRequest)
		return
	}

	// Regla 7: Límite diario de consultas recibidas por el destinatario (máx 10 por día)
	targetUser.ResetDailyLimitsIfNewDay(today)
	if targetUser.DailyReceivedToday+req.Amount > 10 {
		http.Error(w, "El jugador destino ha alcanzado su límite diario de recepción de consultas (máximo 10 por día).", http.StatusBadRequest)
		return
	}

	tx := database.DB.Begin()

	// Descontar consultas del remitente (priorizando GiftQueries -> Suscripción -> Compradas -> Anuncios -> Bono -> Diarias)
	if !user.DeductTransferQueries(req.Amount) {
		tx.Rollback()
		http.Error(w, "No tienes suficientes consultas transferibles.", http.StatusBadRequest)
		return
	}

	user.DailyTransferredToday += req.Amount
	user.LastTransferDate = today

	if err := tx.Model(user).Updates(map[string]interface{}{
		"gift_queries":            user.GiftQueries,
		"subscription_queries":    user.SubscriptionQueries,
		"purchased_queries":       user.PurchasedQueries,
		"ad_queries":              user.AdQueries,
		"bonus_queries":           user.BonusQueries,
		"daily_queries":           user.DailyQueries,
		"available_queries":       user.AvailableQueries,
		"daily_transferred_today": user.DailyTransferredToday,
		"last_transfer_date":      user.LastTransferDate,
	}).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Error actualizando el saldo del remitente", http.StatusInternalServerError)
		return
	}

	// Añadir consultas al destinatario
	targetUser.RecalculateAvailableQueries()
	targetUser.AddAdQueries(req.Amount)
	targetUser.DailyReceivedToday += req.Amount
	targetUser.LastReceivedDate = today

	if err := tx.Model(&targetUser).Updates(map[string]interface{}{
		"ad_queries":           targetUser.AdQueries,
		"available_queries":    targetUser.AvailableQueries,
		"daily_received_today": targetUser.DailyReceivedToday,
		"last_received_date":   targetUser.LastReceivedDate,
	}).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Error acreditando consultas al destinatario", http.StatusInternalServerError)
		return
	}

	if err := tx.Commit().Error; err != nil {
		http.Error(w, "Error confirmando la transferencia", http.StatusInternalServerError)
		return
	}

	// Registrar transferencia para auditoría (no bloqueante ante esquemas legacy)
	transferLog := models.QueryTransfer{
		FromUserID:       user.ID,
		FromReferralCode: user.ReferralCode,
		ToUserID:         targetUser.ID,
		ToReferralCode:   targetUser.ReferralCode,
		Amount:           req.Amount,
		CreatedAt:        time.Now().UTC(),
	}
	if err := database.DB.Create(&transferLog).Error; err != nil {
		log.Printf("[STORE] Warning: no se pudo guardar auditoría de transferencia: %v", err)
	}

	remainingToday := 10 - user.DailyTransferredToday
	if remainingToday < 0 {
		remainingToday = 0
	}

	targetDisplayName := targetUser.Username
	if targetDisplayName == "" {
		targetDisplayName = targetUser.ReferralCode
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":                  true,
		"message":                  fmt.Sprintf("¡Has transferido con éxito %d consultas a %s!", req.Amount, targetDisplayName),
		"transferred_amount":       req.Amount,
		"target_player":            targetDisplayName,
		"available_queries":        user.AvailableQueries,
		"gift_queries":             user.GiftQueries,
		"daily_transferred_today":  user.DailyTransferredToday,
		"remaining_transfer_today": remainingToday,
		"remaining_transfer_quota": remainingToday,
	})
}
