package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
	"gorm.io/gorm"
)

type RedeemReferralRequest struct {
	ReferralCode string `json:"referral_code"`
	DeviceID     string `json:"device_id"`
}

// RedeemReferral processes an invitation code with strict anti-fraud checks.
// Rule: Each invited friend = +5 queries for referrer (up to 10 friends = 50 queries max).
// The invited friend gets +2 welcome queries.
func RedeemReferral(w http.ResponseWriter, r *http.Request) {
	currentUser, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || currentUser == nil {
		http.Error(w, "No autorizado", http.StatusUnauthorized)
		return
	}

	var req RedeemReferralRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Cuerpo de solicitud inválido", http.StatusBadRequest)
		return
	}

	rawCode := extractCleanPlayerCode(req.ReferralCode)
	if rawCode == "" {
		http.Error(w, "El código de invitación es requerido", http.StatusBadRequest)
		return
	}

	// 1. Antifraude: No puedes canjear si ya fuiste referido por alguien
	if currentUser.ReferredByID != nil || currentUser.ReferredByStreamerCode != "" {
		http.Error(w, "Ya has canjeado un código de invitación anteriormente.", http.StatusBadRequest)
		return
	}

	// 2. Buscar al anfitrión por su código (acepta con o sin prefijo "WR", mayúsculas/minúsculas o UUID)
	codeUpper := strings.ToUpper(rawCode)
	codeWithPrefix := codeUpper
	if !strings.HasPrefix(codeWithPrefix, "WR") {
		codeWithPrefix = "WR" + codeWithPrefix
	}
	codeWithoutPrefix := strings.TrimPrefix(codeUpper, "WR")

	var referrer models.User
	if err := database.DB.Where("UPPER(referral_code) = ? OR UPPER(referral_code) = ? OR UPPER(referral_code) = ? OR id::text = ?", codeUpper, codeWithPrefix, codeWithoutPrefix, rawCode).First(&referrer).Error; err != nil {
		// 2.1 Verificar si corresponde a un Código Oficial de Streamer / Creador Afiliado
		var streamer models.StreamerApplication
		if sErr := database.DB.Where("UPPER(promo_code) = ? AND status = 'approved'", codeUpper).First(&streamer).Error; sErr == nil {
			const streamerWelcomeBonus = 3
			currentUser.ReferredByStreamerCode = streamer.PromoCode
			currentUser.AddAdQueries(streamerWelcomeBonus)

			txErr := database.DB.Transaction(func(tx *gorm.DB) error {
				if err := tx.Model(currentUser).Updates(map[string]interface{}{
					"referred_by_streamer_code": currentUser.ReferredByStreamerCode,
					"ad_queries":                currentUser.AdQueries,
					"available_queries":         currentUser.AvailableQueries,
				}).Error; err != nil {
					return err
				}
				return tx.Model(&streamer).Update("total_referrals", gorm.Expr("total_referrals + 1")).Error
			})
			if txErr != nil {
				http.Error(w, "Error al activar código de creador.", http.StatusInternalServerError)
				return
			}

			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"success":           true,
				"message":           "¡Código de Streamer Oficial (" + streamer.Name + ") activado! Recibiste +3 consultas de bienvenida.",
				"available_queries": currentUser.AvailableQueries,
				"milestone_earned":  false,
				"streamer_code":     streamer.PromoCode,
			})
			return
		}

		http.Error(w, "Código de invitación no válido o inexistente.", http.StatusNotFound)
		return
	}

	// 3. Antifraude: No auto-referirse
	if referrer.ID == currentUser.ID || strings.EqualFold(referrer.Email, currentUser.Email) {
		http.Error(w, "No puedes usar tu propio código de invitación.", http.StatusBadRequest)
		return
	}

	// 3.1 Antifraude: No bucles de referidos mutuos (si el anfitrión ya fue referido por ti)
	if referrer.ReferredByID != nil && *referrer.ReferredByID == currentUser.ID {
		http.Error(w, "No puedes canjear el código de un amigo que ya fue invitado por ti.", http.StatusBadRequest)
		return
	}

	// Sincronizar device_id si se envió en la petición y el usuario aún no lo tenía registrado
	if currentUser.DeviceID == "" && req.DeviceID != "" {
		currentUser.DeviceID = req.DeviceID
		database.DB.Model(currentUser).Update("device_id", currentUser.DeviceID)
	}

	// 4. Antifraude: No usar el mismo dispositivo físico
	if currentUser.DeviceID != "" && referrer.DeviceID != "" && currentUser.DeviceID == referrer.DeviceID {
		http.Error(w, "No se permite canjear invitaciones en el mismo dispositivo.", http.StatusBadRequest)
		return
	}

	// 5. Antifraude: Límite de 10 amigos para el anfitrión (5 logros de 2 amigos)
	if referrer.ReferralCount >= 10 {
		http.Error(w, "Este usuario ya alcanzó el límite máximo de 10 amigos invitados.", http.StatusBadRequest)
		return
	}

	var milestoneEarned bool
	var newAvailableQueries int

	// Ejecutar en transacción atómica
	err := database.DB.Transaction(func(tx *gorm.DB) error {
		// Bloquear y recargar al anfitrión dentro de la transacción
		var lockedReferrer models.User
		if err := tx.Where("id = ?", referrer.ID).First(&lockedReferrer).Error; err != nil {
			return err
		}

		if lockedReferrer.ReferralCount >= 10 {
			return errors.New("MAX_LIMIT_REACHED")
		}

		// Actualizar al usuario actual (invitado)
		currentUser.ReferredByID = &lockedReferrer.ID
		const welcomeBonus = 2 // Bono de bienvenida para el invitado
		currentUser.AddAdQueries(welcomeBonus)
		if err := tx.Model(currentUser).Updates(map[string]interface{}{
			"referred_by_id":    currentUser.ReferredByID,
			"device_id":         currentUser.DeviceID,
			"ad_queries":        currentUser.AdQueries,
			"available_queries": currentUser.AvailableQueries,
		}).Error; err != nil {
			return err
		}

		newAvailableQueries = currentUser.AvailableQueries

		// Actualizar al anfitrión
		lockedReferrer.ReferralCount++

		// Recompensa: Cada nuevo amigo = +5 consultas hasta un máximo de 10 amigos (50 consultas)
		if lockedReferrer.ReferralRewardsClaimed < 10 {
			lockedReferrer.ReferralRewardsClaimed++
			lockedReferrer.AddAdQueries(5)
			milestoneEarned = true
		}

		if err := tx.Model(&lockedReferrer).Updates(map[string]interface{}{
			"referral_count":           lockedReferrer.ReferralCount,
			"referral_rewards_claimed": lockedReferrer.ReferralRewardsClaimed,
			"ad_queries":               lockedReferrer.AdQueries,
			"available_queries":        lockedReferrer.AvailableQueries,
		}).Error; err != nil {
			return err
		}

		return nil
	})

	if err != nil {
		if err.Error() == "MAX_LIMIT_REACHED" {
			http.Error(w, "Este usuario ya alcanzó el límite máximo de 10 amigos invitados.", http.StatusBadRequest)
			return
		}
		http.Error(w, "Error al procesar la invitación. Inténtalo de nuevo.", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":           true,
		"message":           "¡Código canjeado con éxito! Recibiste +2 consultas de bienvenida.",
		"available_queries": newAvailableQueries,
		"milestone_earned":  milestoneEarned,
	})
}
