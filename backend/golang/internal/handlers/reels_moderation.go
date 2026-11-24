package handlers

import (
	"context"
	"encoding/json"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"backend/internal/config"
	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/middleware"
	"backend/internal/models"
	"backend/internal/moderation"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

const (
	ModerationStatusPendingScan  = "pending_scan"
	ModerationStatusApproved     = "approved"
	ModerationStatusQuarantined  = "quarantined"
	ModerationStatusRejected     = "rejected"
	ModerationStatusVerifiedSafe = "verified_safe"

	// Umbrales calibrados para comunidades de ~2,000+ usuarios (cuarentena rápida sin permitir brigading)
	QuarantineWeightedThreshold = 3.0  // 3 reportes ponderados -> cuarentena inmediata
	QuarantineViralViewsMin     = 300  // Videos con >=300 vistas exigen ratio mínimo anti-brigading
	QuarantineViralRatioMin     = 0.03 // 3% de las vistas para videos virales
	QuarantineNSFWOverrideScore = 5.0  // Si 5+ puntos reportan +18/Gore, entra a cuarentena aunque sea viral
	MaxStrikesBeforeAutoBan     = 3    // 3 strikes por toxicidad/odio -> ban automático (NSFW/Gore = ban inmediato)
	NewAccountMaxReelsPerDay    = 1    // Cuentas <24h solo pueden subir 1 Brief al día

	DefaultModerationMaxConcurrency = 2
	ModerationQueueWaitTimeout      = 10 * time.Minute
)

var (
	moderationSemOnce sync.Once
	moderationSem     chan struct{}
)

// getModerationSem devuelve el semáforo acotado que limita cuántos procesos FFmpeg+Gemini
// corren simultáneamente, evitando picos de RAM/OOM y saturación de CPU en lanzamientos.
func getModerationSem() chan struct{} {
	moderationSemOnce.Do(func() {
		limit := DefaultModerationMaxConcurrency
		if raw := strings.TrimSpace(config.GetEnv("MODERATION_MAX_CONCURRENCY", "")); raw != "" {
			if n, err := strconv.Atoi(raw); err == nil && n >= 1 && n <= 8 {
				limit = n
			}
		}
		moderationSem = make(chan struct{}, limit)
	})
	return moderationSem
}

// acquireModerationSlot espera turno en el semáforo de moderación antes de descargar video o lanzar FFmpeg.
func acquireModerationSlot(timeout time.Duration) (func(), bool) {
	sem := getModerationSem()
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case sem <- struct{}{}:
		var once sync.Once
		return func() {
			once.Do(func() { <-sem })
		}, true
	case <-timer.C:
		return nil, false
	}
}

// calculateReportWeight calcula el peso anti-brigading de un reporte según antigüedad y Trust Score del usuario.
func calculateReportWeight(user *models.User, now time.Time) float64 {
	if user == nil {
		return 0.25
	}
	trust := user.ReportTrustScore
	if trust <= 0 {
		trust = 1.0
	}
	if trust < 0.1 {
		trust = 0.1
	}
	if trust > 1.5 {
		trust = 1.5
	}

	ageMultiplier := 1.0
	if !user.CreatedAt.IsZero() {
		age := now.Sub(user.CreatedAt)
		switch {
		case age < 24*time.Hour:
			ageMultiplier = 0.25
		case age < 7*24*time.Hour:
			ageMultiplier = 0.60
		default:
			ageMultiplier = 1.0
		}
	}

	weight := math.Round(trust*ageMultiplier*100) / 100
	if weight < 0.1 {
		return 0.1
	}
	return weight
}

// shouldQuarantineReel decide si un reel debe pasar a cuarentena según score ponderado, vistas y motivo.
func shouldQuarantineReel(weightedScore float64, viewsCount int, moderationStatus, dominantReason string) bool {
	// Si ya fue verificado como seguro por el admin, proteger contra brigading
	// (solo permitir re-cuarentena si hay consenso fuerte de +18/Gore)
	if moderationStatus == ModerationStatusVerifiedSafe {
		return dominantReason == "nsfw_gore" && weightedScore >= QuarantineNSFWOverrideScore
	}

	if weightedScore < QuarantineWeightedThreshold {
		return false
	}
	if dominantReason == "nsfw_gore" && weightedScore >= QuarantineNSFWOverrideScore {
		return true
	}
	if viewsCount < QuarantineViralViewsMin {
		return true
	}
	return (weightedScore / float64(viewsCount)) >= QuarantineViralRatioMin
}

// normalizeReportReason normaliza los motivos de reporte (retrocompatible con clientes antiguos).
func normalizeReportReason(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "nsfw_gore", "nsfw", "gore", "sexual", "violence":
		return "nsfw_gore"
	case "harassment_hate", "offensive", "hate", "harassment", "insults":
		return "harassment_hate"
	case "impersonation_stolen", "impersonation", "stolen", "misleading":
		return "impersonation_stolen"
	case "spam", "low_quality":
		return "spam"
	case "off_topic":
		return "off_topic"
	default:
		return "other"
	}
}

// matchBannedFrameHashes verifica a costo $0 si alguno de los dHashes coincide con contenido previamente baneado.
func matchBannedFrameHashes(hashes []string) (bool, string) {
	if database.DB == nil || len(hashes) == 0 {
		return false, ""
	}
	var banned []models.BannedContentHash
	if err := database.DB.Select("frame_hash, reason").Limit(5000).Find(&banned).Error; err != nil || len(banned) == 0 {
		return false, ""
	}
	for _, h := range hashes {
		for _, b := range banned {
			if moderation.HammingDistanceHex(h, b.FrameHash) <= moderation.MaxHammingMatchThreshold {
				return true, b.Reason
			}
		}
	}
	return false, ""
}

// storeBannedFrameHashes guarda los dHashes de un video rechazado por +18/gore para bloquear re-subidas.
func storeBannedFrameHashes(reelID uuid.UUID, hashes []string, reason string) {
	if database.DB == nil || len(hashes) == 0 {
		return
	}
	if strings.TrimSpace(reason) == "" {
		reason = "nsfw_gore"
	}
	for _, h := range hashes {
		if strings.TrimSpace(h) == "" {
			continue
		}
		entry := models.BannedContentHash{
			FrameHash:    h,
			Reason:       reason,
			SourceReelID: &reelID,
		}
		_ = database.DB.Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "frame_hash"}},
			DoNothing: true,
		}).Create(&entry).Error
	}
}

// banUserAndDeviceImmediately banea permanentemente al usuario y revoca su sesión JWT al instante.
// Nota: auth.go y auth_manual.go ya bloquean automáticamente cualquier login/registro futuro desde su device_id.
func banUserAndDeviceImmediately(userID uuid.UUID, reason string) {
	if database.DB == nil || userID == uuid.Nil {
		return
	}
	err := database.DB.Model(&models.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
		"banned":             true,
		"session_token":      "",
		"moderation_strikes": MaxStrikesBeforeAutoBan,
	}).Error
	if err != nil {
		log.Printf("[Moderation] Error baneando usuario %s: %v", userID, err)
		return
	}
	// Desactivar todos los reels activos del usuario baneado
	_ = database.DB.Model(&models.Reel{}).Where("creator_id = ?", userID).Updates(map[string]interface{}{
		"active":            false,
		"moderation_status": ModerationStatusRejected,
	}).Error
	log.Printf("[Moderation] 🚫 Usuario y dispositivo baneados inmediatamente (user=%s, motivo=%s)", userID, reason)
}

// applyModerationStrike suma 1 strike al usuario; si llega a 3 strikes, aplica ban automático.
func applyModerationStrike(userID uuid.UUID, reason string) (newStrikes int, bannedNow bool) {
	if database.DB == nil || userID == uuid.Nil {
		return 0, false
	}
	var user models.User
	if err := database.DB.Select("id, moderation_strikes, banned").First(&user, "id = ?", userID).Error; err != nil {
		return 0, false
	}
	newStrikes = user.ModerationStrikes + 1
	updates := map[string]interface{}{
		"moderation_strikes": newStrikes,
	}
	if newStrikes >= MaxStrikesBeforeAutoBan {
		updates["banned"] = true
		updates["session_token"] = ""
		bannedNow = true
	}
	_ = database.DB.Model(&models.User{}).Where("id = ?", userID).Updates(updates).Error
	if bannedNow {
		_ = database.DB.Model(&models.Reel{}).Where("creator_id = ?", userID).Update("active", false).Error
		log.Printf("[Moderation] 🚫 Usuario baneado por alcanzar %d strikes (user=%s, motivo=%s)", newStrikes, userID, reason)
	}
	return newStrikes, bannedNow
}

// RunProactiveReelModeration ejecuta el escaneo preventivo al subir un video:
// 1) Extrae hasta 5 frames con FFmpeg y calcula sus dHashes.
// 2) Verifica contra banned_content_hashes (costo $0).
// 3) Analiza los frames + título/descripción con Gemini Flash (ThinkingBudget=0).
// 4) Aprueba, pone en cuarentena o rechaza + banea dispositivo si detecta +18/Gore.
func RunProactiveReelModeration(reelID uuid.UUID) {
	go func() {
		if database.DB == nil {
			return
		}
		release, acquired := acquireModerationSlot(ModerationQueueWaitTimeout)
		if !acquired {
			log.Printf("[Moderation] Cola saturada esperando turno para reel %s; pasando a cuarentena para revisión", reelID)
			now := time.Now().UTC()
			_ = database.DB.Model(&models.Reel{}).Where("id = ?", reelID).Updates(map[string]interface{}{
				"active":                false,
				"silenced_by_reports":   true,
				"moderation_status":     ModerationStatusQuarantined,
				"moderation_reason":     "Cola de escaneo temporalmente saturada; requiere revisión manual",
				"moderation_checked_at": &now,
			}).Error
			return
		}
		defer release()

		ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
		defer cancel()

		var reel models.Reel
		if err := database.DB.First(&reel, "id = ?", reelID).Error; err != nil {
			return
		}
		resolveReelMediaURLs(&reel)

		frames, hashes, extractErr := moderation.ExtractKeyframesAndHashes(ctx, reel.VideoURL, reel.ThumbnailURL, reel.DurationSeconds)
		primaryHash := ""
		if len(hashes) > 0 {
			primaryHash = hashes[0]
		}

		// Paso 1: Deduplicación / Hash Matching a costo $0 contra contenido previamente baneado
		if matched, matchedReason := matchBannedFrameHashes(hashes); matched {
			now := time.Now().UTC()
			_ = database.DB.Model(&models.Reel{}).Where("id = ?", reel.ID).Updates(map[string]interface{}{
				"active":                false,
				"silenced_by_reports":   true,
				"moderation_status":     ModerationStatusRejected,
				"moderation_reason":     "Contenido idéntico a material prohibido previamente (" + matchedReason + ")",
				"moderation_score":      1.0,
				"moderation_checked_at": &now,
				"content_hash":          primaryHash,
			}).Error
			cleanupReelStorageFiles(&reel)
			banUserAndDeviceImmediately(reel.CreatorID, "reupload_banned_hash_"+matchedReason)
			return
		}

		// Paso 2: Si Vertex AI no está inicializado (ej. entorno de pruebas sin credenciales), enviar a revisión o aprobar
		if !gemini.IsModerationAvailable() {
			now := time.Now().UTC()
			_ = database.DB.Model(&models.Reel{}).Where("id = ?", reel.ID).Updates(map[string]interface{}{
				"active":                true,
				"moderation_status":     ModerationStatusApproved,
				"moderation_reason":     "ia_no_configurada_dev",
				"moderation_checked_at": &now,
				"content_hash":          primaryHash,
			}).Error
			return
		}

		if extractErr != nil {
			log.Printf("[Moderation] Aviso extrayendo frames de reel %s (se moderará texto): %v", reel.ID, extractErr)
		}

		// Paso 3: Escaneo multimodal con Gemini 2.5 Flash (frames + título + descripción)
		verdict, err := gemini.ModerateReelFrames(ctx, reel.Title, reel.Description, frames)
		now := time.Now().UTC()
		if err != nil {
			// Fail-safe: si falla la API temporalmente, dejar en cuarentena para revisión manual (nunca exponer gore)
			log.Printf("[Moderation] Error escaneando reel %s con Gemini: %v", reel.ID, err)
			_ = database.DB.Model(&models.Reel{}).Where("id = ?", reel.ID).Updates(map[string]interface{}{
				"active":                false,
				"silenced_by_reports":   true,
				"moderation_status":     ModerationStatusQuarantined,
				"moderation_reason":     "Error temporal en escaneo automático; requiere revisión manual",
				"moderation_checked_at": &now,
				"content_hash":          primaryHash,
			}).Error
			return
		}

		// Decisión basada en severidad y confianza
		if !verdict.Safe && (verdict.Category == "nsfw" || verdict.Category == "gore") && verdict.Confidence >= 0.85 {
			// Tolerancia cero para +18 / Gore: eliminar media, guardar hashes, banear cuenta + dispositivo
			_ = database.DB.Model(&models.Reel{}).Where("id = ?", reel.ID).Updates(map[string]interface{}{
				"active":                false,
				"silenced_by_reports":   true,
				"moderation_status":     ModerationStatusRejected,
				"moderation_reason":     verdict.Reason,
				"moderation_score":      verdict.Confidence,
				"moderation_checked_at": &now,
				"content_hash":          primaryHash,
			}).Error
			storeBannedFrameHashes(reel.ID, hashes, verdict.Category)
			cleanupReelStorageFiles(&reel)
			banUserAndDeviceImmediately(reel.CreatorID, verdict.Category)
			return
		}

		if !verdict.Safe && verdict.Confidence >= 0.50 {
			// Confianza media o discurso de odio en texto/imagen -> Cuarentena para panel admin
			_ = database.DB.Model(&models.Reel{}).Where("id = ?", reel.ID).Updates(map[string]interface{}{
				"active":                false,
				"silenced_by_reports":   true,
				"moderation_status":     ModerationStatusQuarantined,
				"moderation_reason":     verdict.Reason,
				"moderation_score":      verdict.Confidence,
				"moderation_checked_at": &now,
				"content_hash":          primaryHash,
			}).Error
			return
		}

		// Video limpio -> Publicar en el feed de Brief
		_ = database.DB.Model(&models.Reel{}).Where("id = ?", reel.ID).Updates(map[string]interface{}{
			"active":                true,
			"silenced_by_reports":   false,
			"moderation_status":     ModerationStatusApproved,
			"moderation_reason":     "",
			"moderation_score":      verdict.Confidence,
			"moderation_checked_at": &now,
			"content_hash":          primaryHash,
		}).Error
		invalidateReelsFeedCache()
	}()
}

// RunQuarantineAIReview se dispara SOLO bajo demanda cuando un video llega a cuarentena por reportes.
// Evita gastar cuota en audio salvo que existan reportes reales de toxicidad/odio.
func RunQuarantineAIReview(reelID uuid.UUID, dominantReason string) {
	go func() {
		if database.DB == nil || !gemini.IsModerationAvailable() {
			return
		}
		release, acquired := acquireModerationSlot(ModerationQueueWaitTimeout)
		if !acquired {
			log.Printf("[Moderation] Cola saturada para revisión de cuarentena del reel %s", reelID)
			return
		}
		defer release()

		ctx, cancel := context.WithTimeout(context.Background(), 50*time.Second)
		defer cancel()

		var reel models.Reel
		if err := database.DB.First(&reel, "id = ?", reelID).Error; err != nil {
			return
		}
		resolveReelMediaURLs(&reel)

		now := time.Now().UTC()

		switch dominantReason {
		case "nsfw_gore":
			frames, hashes, err := moderation.ExtractKeyframesAndHashes(ctx, reel.VideoURL, reel.ThumbnailURL, reel.DurationSeconds)
			if err != nil {
				return
			}
			verdict, err := gemini.ModerateReelFrames(ctx, reel.Title, reel.Description, frames)
			if err != nil {
				return
			}
			if !verdict.Safe && (verdict.Category == "nsfw" || verdict.Category == "gore") && verdict.Confidence >= 0.85 {
				_ = database.DB.Model(&models.Reel{}).Where("id = ?", reel.ID).Updates(map[string]interface{}{
					"active":                false,
					"silenced_by_reports":   true,
					"moderation_status":     ModerationStatusRejected,
					"moderation_reason":     "Confirmado tras reportes: " + verdict.Reason,
					"moderation_score":      verdict.Confidence,
					"moderation_checked_at": &now,
				}).Error
				storeBannedFrameHashes(reel.ID, hashes, verdict.Category)
				cleanupReelStorageFiles(&reel)
				banUserAndDeviceImmediately(reel.CreatorID, "reported_"+verdict.Category)
				return
			}
			_ = database.DB.Model(&models.Reel{}).Where("id = ?", reel.ID).Updates(map[string]interface{}{
				"moderation_reason":     "Revisión IA tras reportes (+18/Gore): " + verdict.Reason,
				"moderation_score":      verdict.Confidence,
				"moderation_checked_at": &now,
			}).Error

		case "harassment_hate":
			// Extraer audio ligero (32kbps mono) y analizar con Gemini Flash SOLO bajo demanda
			audioBytes, err := moderation.ExtractAudioTrack(ctx, reel.VideoURL)
			if err != nil {
				log.Printf("[Moderation] Sin audio extraíble para reel %s: %v", reel.ID, err)
				return
			}
			verdict, err := gemini.ModerateReelAudioOnDemand(ctx, reel.Title, reel.Description, audioBytes, "audio/mpeg")
			if err != nil {
				log.Printf("[Moderation] Error analizando audio de reel %s: %v", reel.ID, err)
				return
			}
			updates := map[string]interface{}{
				"moderation_reason":     "Audio IA: " + verdict.Reason,
				"moderation_score":      verdict.Confidence,
				"moderation_checked_at": &now,
			}
			if !verdict.Safe && verdict.Confidence >= 0.85 {
				// Queda silenciado y pasa a tu panel con alta prioridad + 1 strike al creador
				applyModerationStrike(reel.CreatorID, "hate_harassment_audio")
			}
			_ = database.DB.Model(&models.Reel{}).Where("id = ?", reel.ID).Updates(updates).Error

		default:
			// Suplantación / contenido copiado / spam -> directo a revisión humana en panel admin sin gastar IA
			_ = database.DB.Model(&models.Reel{}).Where("id = ?", reel.ID).Updates(map[string]interface{}{
				"moderation_reason":     "En cuarentena por reportes (" + dominantReason + ") para revisión humana",
				"moderation_checked_at": &now,
			}).Error
		}
	}()
}

// ==============================================================================
// BLOQUEO DE USUARIOS (REQUISITO OBLIGATORIO GOOGLE PLAY / APP STORE UGC)
// ==============================================================================

// ToggleBlockUser bloquea o desbloquea a otro usuario y oculta de inmediato todos sus Briefs y comentarios.
func ToggleBlockUser(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	targetUserID, err := uuid.Parse(chi.URLParam(r, "user_id"))
	if err != nil {
		http.Error(w, `{"error":"ID de usuario inválido"}`, http.StatusBadRequest)
		return
	}
	if targetUserID == user.ID {
		http.Error(w, `{"error":"No puedes bloquearte a ti mismo"}`, http.StatusBadRequest)
		return
	}

	var blocked bool
	err = database.DB.Transaction(func(tx *gorm.DB) error {
		var existing models.UserBlock
		errFind := tx.Where("blocker_id = ? AND blocked_id = ?", user.ID, targetUserID).First(&existing).Error
		if errFind == nil {
			if errDel := tx.Delete(&existing).Error; errDel != nil {
				return errDel
			}
			blocked = false
			return nil
		}

		entry := models.UserBlock{
			BlockerID: user.ID,
			BlockedID: targetUserID,
		}
		if errIns := tx.Create(&entry).Error; errIns != nil {
			return errIns
		}
		// Al bloquear, eliminar relación de seguimiento en ambos sentidos
		_ = tx.Where("(follower_id = ? AND following_id = ?) OR (follower_id = ? AND following_id = ?)",
			user.ID, targetUserID, targetUserID, user.ID).Delete(&models.UserFollow{}).Error
		blocked = true
		return nil
	})

	if err != nil {
		http.Error(w, `{"error":"Error al actualizar bloqueo de usuario"}`, http.StatusInternalServerError)
		return
	}

	msg := "Usuario bloqueado. Ya no verás sus videos ni comentarios."
	if !blocked {
		msg = "Usuario desbloqueado."
	}
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"blocked": blocked,
		"message": msg,
	})
}

// GetBlockedUsers devuelve los IDs de usuarios bloqueados por el usuario autenticado.
func GetBlockedUsers(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	var blockedIDs []uuid.UUID
	if err := database.DB.Model(&models.UserBlock{}).
		Where("blocker_id = ?", user.ID).
		Pluck("blocked_id", &blockedIDs).Error; err != nil {
		http.Error(w, `{"error":"Error consultando usuarios bloqueados"}`, http.StatusInternalServerError)
		return
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"blocked_user_ids": blockedIDs,
		"count":            len(blockedIDs),
	})
}

// getBlockedUserIDsForViewer helper rápido para filtrar feed y comentarios.
func getBlockedUserIDsForViewer(viewer *models.User) []uuid.UUID {
	if viewer == nil || database.DB == nil {
		return nil
	}
	var ids []uuid.UUID
	_ = database.DB.Model(&models.UserBlock{}).
		Where("blocker_id = ?", viewer.ID).
		Pluck("blocked_id", &ids).Error
	return ids
}
