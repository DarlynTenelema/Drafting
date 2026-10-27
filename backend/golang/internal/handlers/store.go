package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
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
		Description:  "50 consultas exclusivas para nuevos reclutas",
	},
	"pack_plus": {
		ID:           "pack_plus",
		Name:         "Pack Plus",
		PriceUSD:     0.49,
		TotalQueries: 50,
		BaseQueries:  50,
		BonusQueries: 0,
		Tag:          "Económico",
		IsStarter:    false,
		Description:  "50 consultas permanentes sin fecha de vencimiento",
	},
	"pack_pro": {
		ID:           "pack_pro",
		Name:         "Pack Pro",
		PriceUSD:     0.99,
		TotalQueries: 150,
		BaseQueries:  100,
		BonusQueries: 50,
		Tag:          "Más Popular",
		IsStarter:    false,
		Description:  "100 consultas + 50 de regalo",
	},
	"pack_ultra": {
		ID:           "pack_ultra",
		Name:         "Pack Ultra",
		PriceUSD:     2.99,
		TotalQueries: 400,
		BaseQueries:  300,
		BonusQueries: 100,
		Tag:          "Mejor Valor",
		IsStarter:    false,
		Description:  "300 consultas + 100 de regalo",
	},
}

var AvailableSubscriptions = map[string]SubscriptionConfig{
	"sub_plus": {
		ID:              "sub_plus",
		Name:            "Plan Plus",
		PriceUSD:        0.99,
		QueriesPerMonth: 200,
		Tag:             "Básico Mensual",
		Description:     "200 consultas/mes + Enviar hasta 10/día a amigos",
	},
	"sub_pro": {
		ID:              "sub_pro",
		Name:            "Plan Pro",
		PriceUSD:        1.99,
		QueriesPerMonth: 300,
		Tag:             "Avanzado",
		Description:     "300 consultas/mes + Enviar hasta 10/día a amigos",
	},
	"sub_ultra": {
		ID:              "sub_ultra",
		Name:            "Plan Ultra",
		PriceUSD:        2.99,
		QueriesPerMonth: 500,
		Tag:             "Challenger",
		Description:     "500 consultas/mes + Enviar hasta 10/día a amigos",
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

// GetStoreCatalog retorna los paquetes y suscripciones disponibles según el estado del usuario
func GetStoreCatalog(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	today := time.Now().UTC().Format("2006-01-02")
	user.ResetDailyLimitsIfNewDay(today)
	user.CheckSubscriptionExpiry()

	// Filtrar catálogo: si ya compró el starter pack, no se muestra
	packsList := make([]PackConfig, 0)
	orderPacks := []string{"pack_starter", "pack_plus", "pack_pro", "pack_ultra"}
	for _, id := range orderPacks {
		pack := AvailablePacks[id]
		if pack.IsStarter && user.HasPurchasedStarter {
			continue // Desaparece para siempre de la tienda
		}
		packsList = append(packsList, pack)
	}

	subsList := make([]SubscriptionConfig, 0)
	orderSubs := []string{"sub_plus", "sub_pro", "sub_ultra"}
	for _, id := range orderSubs {
		subsList = append(subsList, AvailableSubscriptions[id])
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
		"available_queries":        user.AvailableQueries,
		"daily_transferred_today":  user.DailyTransferredToday,
		"remaining_transfer_quota": remainingTransferQuota,
		"can_transfer":             user.IsSubscribed() && remainingTransferQuota > 0,
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

// PurchasePack gestiona la adquisición de un paquete de consultas
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
		http.Error(w, "Paquete no válido.", http.StatusBadRequest)
		return
	}

	// Regla del Starter Pack: Solo una única vez
	if pack.IsStarter && user.HasPurchasedStarter {
		http.Error(w, "El Pack Starter ya ha sido adquirido previamente y no está disponible.", http.StatusForbidden)
		return
	}

	if req.Provider == "" {
		req.Provider = "google_play"
	}
	if req.ProviderTransactionID == "" {
		req.ProviderTransactionID = fmt.Sprintf("gp_%d", time.Now().UnixNano())
	}

	// Idempotencia: Verificar si esta transacción ya fue registrada como completada
	var existing models.Transaction
	if err := database.DB.Where("provider_transaction_id = ? AND status = 'completed'", req.ProviderTransactionID).First(&existing).Error; err == nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success":               true,
			"message":               "Transacción ya procesada previamente.",
			"pack_id":               pack.ID,
			"queries_added":         0,
			"available_queries":     user.AvailableQueries,
			"purchased_queries":     user.PurchasedQueries,
			"has_purchased_starter": user.HasPurchasedStarter,
		})
		return
	}

	// Transacción en base de datos
	tx := database.DB.Begin()

	if pack.IsStarter {
		user.HasPurchasedStarter = true
	}
	user.AddPurchasedQueries(pack.TotalQueries)

	if err := tx.Save(user).Error; err != nil {
		tx.Rollback()
		log.Printf("[STORE] Error actualizando usuario tras compra: %v", err)
		http.Error(w, fmt.Sprintf("Error actualizando saldo de consultas: %v", err), http.StatusInternalServerError)
		return
	}

	transactionRecord := models.Transaction{
		UserID:                user.ID,
		Type:                  "pack",
		ItemKey:               pack.ID,
		AmountUSD:             pack.PriceUSD,
		QueriesAdded:          pack.TotalQueries,
		Provider:              req.Provider,
		ProviderTransactionID: req.ProviderTransactionID,
		Status:                "completed",
		CreatedAt:             time.Now().UTC(),
	}

	if err := tx.Create(&transactionRecord).Error; err != nil {
		log.Printf("[STORE] Warning: no se pudo guardar registro de transacción: %v", err)
	}

	tx.Commit()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":               true,
		"message":               fmt.Sprintf("¡Compra exitosa! Se han añadido %d consultas a tu cuenta.", pack.TotalQueries),
		"pack_id":               pack.ID,
		"queries_added":         pack.TotalQueries,
		"available_queries":     user.AvailableQueries,
		"purchased_queries":     user.PurchasedQueries,
		"has_purchased_starter": user.HasPurchasedStarter,
	})
}

type SubscribeRequest struct {
	PlanID                string `json:"plan_id"`
	ProviderTransactionID string `json:"provider_transaction_id"`
	Provider              string `json:"provider"`
	PurchaseToken         string `json:"purchase_token,omitempty"`
	PackageName           string `json:"package_name,omitempty"`
}

// Subscribe activa o renueva la suscripción mensual del usuario
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

	if req.Provider == "" {
		req.Provider = "google_play"
	}
	if req.ProviderTransactionID == "" {
		req.ProviderTransactionID = fmt.Sprintf("sub_%d", time.Now().UnixNano())
	}

	// Idempotencia: Verificar si esta transacción ya fue registrada como completada
	var existing models.Transaction
	if err := database.DB.Where("provider_transaction_id = ? AND status = 'completed'", req.ProviderTransactionID).First(&existing).Error; err == nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success":              true,
			"message":              "Suscripción ya procesada previamente.",
			"subscription_plan":    user.SubscriptionPlan,
			"subscription_queries": user.SubscriptionQueries,
			"subscription_ends_at": user.SubscriptionEndsAt,
			"available_queries":    user.AvailableQueries,
		})
		return
	}

	tx := database.DB.Begin()

	// Las consultas de suscripción reemplazan a las anteriores (no se acumulan con meses pasados)
	expiryDate := time.Now().UTC().AddDate(0, 1, 0)
	user.SubscriptionPlan = plan.ID
	user.SubscriptionQueries = plan.QueriesPerMonth
	user.SubscriptionEndsAt = &expiryDate
	user.RecalculateAvailableQueries()

	if err := tx.Save(user).Error; err != nil {
		tx.Rollback()
		log.Printf("[STORE] Error actualizando usuario tras suscripción: %v", err)
		http.Error(w, fmt.Sprintf("Error actualizando la suscripción: %v", err), http.StatusInternalServerError)
		return
	}

	transactionRecord := models.Transaction{
		UserID:                user.ID,
		Type:                  "subscription",
		ItemKey:               plan.ID,
		AmountUSD:             plan.PriceUSD,
		QueriesAdded:          plan.QueriesPerMonth,
		Provider:              req.Provider,
		ProviderTransactionID: req.ProviderTransactionID,
		Status:                "completed",
		CreatedAt:             time.Now().UTC(),
	}

	if err := tx.Create(&transactionRecord).Error; err != nil {
		log.Printf("[STORE] Warning: no se pudo guardar registro de suscripción: %v", err)
	}

	tx.Commit()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":              true,
		"message":              fmt.Sprintf("¡Suscripción al %s activada! Tienes %d consultas para este mes.", plan.Name, plan.QueriesPerMonth),
		"subscription_plan":    user.SubscriptionPlan,
		"subscription_queries": user.SubscriptionQueries,
		"subscription_ends_at": user.SubscriptionEndsAt,
		"available_queries":    user.AvailableQueries,
	})
}

type TransferRequest struct {
	TargetPlayerID string `json:"target_player_id"` // Puede ser código de referido (ej: "EW3J43" o "WREW3J43") o UUID
	Amount         int    `json:"amount"`
}

// TransferQueries permite a un suscriptor activo transferir hasta 10 consultas por día a un amigo
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

	// Regla 1: Solo usuarios con suscripción activa pueden transferir
	if !user.IsSubscribed() {
		http.Error(w, "Solo los usuarios con una suscripción activa pueden compartir consultas con amigos.", http.StatusForbidden)
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

	// Regla 4: Verificar que el remitente tenga saldo suficiente
	if user.AvailableQueries < req.Amount {
		http.Error(w, "No tienes suficientes consultas disponibles para realizar la transferencia.", http.StatusBadRequest)
		return
	}

	// Regla 5: Buscar al destinatario
	rawTarget := strings.TrimSpace(req.TargetPlayerID)
	if rawTarget == "" {
		http.Error(w, "Debes proporcionar el ID o código del jugador.", http.StatusBadRequest)
		return
	}

	targetCodeWithPrefix := strings.ToUpper(rawTarget)
	if !strings.HasPrefix(targetCodeWithPrefix, "WR") {
		targetCodeWithPrefix = "WR" + targetCodeWithPrefix
	}

	var targetUser models.User
	err := database.DB.Where("referral_code = ? OR referral_code = ? OR id::text = ?", targetCodeWithPrefix, rawTarget, rawTarget).First(&targetUser).Error
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

	// Descontar consultas del remitente (priorizando consultas de suscripción o compradas)
	deducted := 0
	toDeduct := req.Amount

	if user.SubscriptionQueries >= toDeduct {
		user.SubscriptionQueries -= toDeduct
		deducted = toDeduct
	} else {
		deducted += user.SubscriptionQueries
		toDeduct -= user.SubscriptionQueries
		user.SubscriptionQueries = 0

		if user.PurchasedQueries >= toDeduct {
			user.PurchasedQueries -= toDeduct
			deducted += toDeduct
		} else {
			deducted += user.PurchasedQueries
			toDeduct -= user.PurchasedQueries
			user.PurchasedQueries = 0

			if user.AdQueries >= toDeduct {
				user.AdQueries -= toDeduct
				deducted += toDeduct
			} else {
				deducted += user.AdQueries
				user.AdQueries = 0
			}
		}
	}

	user.DailyTransferredToday += req.Amount
	user.LastTransferDate = today
	user.RecalculateAvailableQueries()

	if err := tx.Save(user).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Error actualizando el saldo del remitente", http.StatusInternalServerError)
		return
	}

	// Añadir consultas al destinatario
	targetUser.AddAdQueries(req.Amount)
	targetUser.DailyReceivedToday += req.Amount
	targetUser.LastReceivedDate = today

	if err := tx.Save(&targetUser).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Error acreditando consultas al destinatario", http.StatusInternalServerError)
		return
	}

	// Registrar transferencia para auditoría
	transferLog := models.QueryTransfer{
		FromUserID:       user.ID,
		FromReferralCode: user.ReferralCode,
		ToUserID:         targetUser.ID,
		ToReferralCode:   targetUser.ReferralCode,
		Amount:           req.Amount,
		CreatedAt:        time.Now().UTC(),
	}

	if err := tx.Create(&transferLog).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Error registrando la transferencia", http.StatusInternalServerError)
		return
	}

	tx.Commit()

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
		"success":                 true,
		"message":                 fmt.Sprintf("¡Has transferido con éxito %d consultas a %s!", req.Amount, targetDisplayName),
		"transferred_amount":      req.Amount,
		"target_player":           targetDisplayName,
		"available_queries":       user.AvailableQueries,
		"daily_transferred_today": user.DailyTransferredToday,
		"remaining_transfer_today": remainingToday,
	})
}
