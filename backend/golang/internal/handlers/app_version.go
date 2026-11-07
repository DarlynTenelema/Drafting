package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"backend/internal/config"
	"backend/internal/database"
	"backend/internal/models"
)

// AppVersionInfo representa el estado de versión oficial en Google Play y políticas de auto-actualización
type AppVersionInfo struct {
	LatestVersionCode      int               `json:"latest_version_code"`
	LatestVersionName      string            `json:"latest_version_name"`
	MinRequiredVersionCode int               `json:"min_required_version_code"`
	ForceUpdate            bool              `json:"force_update"`
	UpdateMode             string            `json:"update_mode"` // "flexible" (estilo TikTok en 2do plano) | "immediate" (obligatoria)
	PlayStoreURL           string            `json:"play_store_url"`
	MarketURI              string            `json:"market_uri"`
	ReleaseNotes           string            `json:"release_notes"`
	ReleaseNotesI18n       map[string]string `json:"release_notes_i18n"`
	UpdatedAt              time.Time         `json:"updated_at"`
}

var (
	versionMutex   sync.RWMutex
	runtimeVersion *AppVersionInfo
)

// GetCurrentAppVersionInfo construye la configuración vigente de versión de la app (combinando BD y Env)
func GetCurrentAppVersionInfo() AppVersionInfo {
	versionMutex.RLock()
	if runtimeVersion != nil {
		cp := *runtimeVersion
		versionMutex.RUnlock()
		return cp
	}
	versionMutex.RUnlock()

	latestCode, err := strconv.Atoi(config.GetEnv("LATEST_APP_VERSION_CODE", "38"))
	if err != nil || latestCode <= 0 {
		latestCode = 38
	}

	minRequiredCode, err := strconv.Atoi(config.GetEnv("MIN_REQUIRED_VERSION_CODE", "37"))
	if err != nil || minRequiredCode <= 0 {
		minRequiredCode = 37
	}

	latestName := config.GetEnv("LATEST_APP_VERSION_NAME", "1.0.6")
	forceUpdate := strings.EqualFold(config.GetEnv("FORCE_APP_UPDATE", "false"), "true")
	updateMode := config.GetEnv("APP_UPDATE_MODE", "flexible")
	if forceUpdate {
		updateMode = "immediate"
	}

	notesES := config.GetEnv("APP_RELEASE_NOTES_ES", "• Nuevo sistema de Eventos y alertas de directos en vivo.\n• Muro y Ranking de Donadores con enlaces directos a Twitch, Kick y TikTok.\n• Soporte multi-idioma profesional (ES, PT, EN, FR) en app y análisis IA.\n• Mejoras de velocidad y actualización inteligente.")
	notesPT := config.GetEnv("APP_RELEASE_NOTES_PT", "• Novo sistema de Eventos e alertas de lives ao vivo.\n• Ranking de Apoiadores com links diretos para Twitch, Kick e TikTok.\n• Suporte multi-idioma profissional (ES, PT, EN, FR) no app e na IA.\n• Melhorias de desempenho e atualização automática.")
	notesEN := config.GetEnv("APP_RELEASE_NOTES_EN", "• New Events hub & real-time Live Stream alerts.\n• Supporters Ranking with direct links to Twitch, Kick, and TikTok.\n• Full professional multi-language support (ES, PT, EN, FR) for UI & AI Draft.\n• Performance improvements and smart auto-update.")
	notesFR := config.GetEnv("APP_RELEASE_NOTES_FR", "• Nouveau centre d'Événements et alertes de directs en temps réel.\n• Classement des Donateurs avec liens directs vers Twitch, Kick et TikTok.\n• Support multilingue professionnel (ES, PT, EN, FR) pour l'application et l'IA.\n• Améliorations de performance et mise à jour automatique.")

	info := AppVersionInfo{
		LatestVersionCode:      latestCode,
		LatestVersionName:      latestName,
		MinRequiredVersionCode: minRequiredCode,
		ForceUpdate:            forceUpdate,
		UpdateMode:             updateMode,
		PlayStoreURL:           "https://play.google.com/store/apps/details?id=com.drafting.app",
		MarketURI:              "market://details?id=com.drafting.app",
		ReleaseNotes:           notesES,
		ReleaseNotesI18n: map[string]string{
			"es": notesES,
			"pt": notesPT,
			"en": notesEN,
			"fr": notesFR,
		},
		UpdatedAt: time.Now().UTC(),
	}

	// Si existe una configuración persistida en PostgreSQL con versión >= a la de entorno, cargarla
	if db := database.GetDB(); db != nil {
		var saved models.AppVersionConfig
		if err := db.Where("id = ?", "current").First(&saved).Error; err == nil && saved.LatestVersionCode >= info.LatestVersionCode {
			info.LatestVersionCode = saved.LatestVersionCode
			if strings.TrimSpace(saved.LatestVersionName) != "" {
				info.LatestVersionName = saved.LatestVersionName
			}
			if saved.MinRequiredVersionCode > 0 {
				info.MinRequiredVersionCode = saved.MinRequiredVersionCode
			}
			info.ForceUpdate = saved.ForceUpdate
			if saved.UpdateMode == "immediate" || saved.UpdateMode == "flexible" {
				info.UpdateMode = saved.UpdateMode
			}
			if info.ForceUpdate {
				info.UpdateMode = "immediate"
			}
			if strings.TrimSpace(saved.ReleaseNotesES) != "" {
				info.ReleaseNotes = saved.ReleaseNotesES
				info.ReleaseNotesI18n["es"] = saved.ReleaseNotesES
			}
			if strings.TrimSpace(saved.ReleaseNotesPT) != "" {
				info.ReleaseNotesI18n["pt"] = saved.ReleaseNotesPT
			}
			if strings.TrimSpace(saved.ReleaseNotesEN) != "" {
				info.ReleaseNotesI18n["en"] = saved.ReleaseNotesEN
			}
			if strings.TrimSpace(saved.ReleaseNotesFR) != "" {
				info.ReleaseNotesI18n["fr"] = saved.ReleaseNotesFR
			}
			if !saved.UpdatedAt.IsZero() {
				info.UpdatedAt = saved.UpdatedAt
			}
		}
	}

	versionMutex.Lock()
	runtimeVersion = &info
	versionMutex.Unlock()

	return info
}

// GetAppVersion devuelve la información de versión actual y evalúa si el cliente necesita actualizarse
func GetAppVersion(w http.ResponseWriter, r *http.Request) {
	info := GetCurrentAppVersionInfo()

	clientCodeStr := strings.TrimSpace(r.URL.Query().Get("version_code"))
	lang := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("lang")))
	if len(lang) >= 2 {
		lang = lang[:2]
	}

	if localized, ok := info.ReleaseNotesI18n[lang]; ok && localized != "" {
		info.ReleaseNotes = localized
	}

	hasUpdate := false
	mustForceUpdate := info.ForceUpdate
	clientCode := 0

	if clientCodeStr != "" {
		if parsed, err := strconv.Atoi(clientCodeStr); err == nil && parsed > 0 {
			clientCode = parsed
			if clientCode < info.LatestVersionCode {
				hasUpdate = true
			}
			if clientCode < info.MinRequiredVersionCode {
				hasUpdate = true
				mustForceUpdate = true
				info.UpdateMode = "immediate"
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"latest_version_code":       info.LatestVersionCode,
		"latest_version_name":       info.LatestVersionName,
		"min_required_version_code": info.MinRequiredVersionCode,
		"client_version_code":       clientCode,
		"has_update":                hasUpdate,
		"force_update":              mustForceUpdate,
		"update_mode":               info.UpdateMode,
		"play_store_url":            info.PlayStoreURL,
		"market_uri":                info.MarketURI,
		"release_notes":             info.ReleaseNotes,
		"release_notes_i18n":        info.ReleaseNotesI18n,
		"updated_at":                info.UpdatedAt,
	})
}

type UpdateAppVersionRequest struct {
	AdminSecret            string            `json:"admin_secret"`
	LatestVersionCode      int               `json:"latest_version_code"`
	LatestVersionName      string            `json:"latest_version_name"`
	MinRequiredVersionCode int               `json:"min_required_version_code"`
	ForceUpdate            bool              `json:"force_update"`
	UpdateMode             string            `json:"update_mode"`
	ReleaseNotes           string            `json:"release_notes"`
	ReleaseNotesI18n       map[string]string `json:"release_notes_i18n"`
}

// SetAppVersion permite actualizar en caliente y persistir en PostgreSQL qué versión está activa en Google Play
func SetAppVersion(w http.ResponseWriter, r *http.Request) {
	var req UpdateAppVersionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid payload", http.StatusBadRequest)
		return
	}

	expectedSecret := config.GetEnv("ADMIN_SECRET", config.GetEnv("JWT_SECRET", ""))
	headerSecret := strings.TrimSpace(r.Header.Get("X-Admin-Secret"))
	providedSecret := strings.TrimSpace(req.AdminSecret)
	if providedSecret == "" {
		providedSecret = headerSecret
	}

	if expectedSecret == "" || providedSecret != expectedSecret {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	current := GetCurrentAppVersionInfo()
	if req.LatestVersionCode > 0 {
		current.LatestVersionCode = req.LatestVersionCode
	}
	if strings.TrimSpace(req.LatestVersionName) != "" {
		current.LatestVersionName = strings.TrimSpace(req.LatestVersionName)
	}
	if req.MinRequiredVersionCode > 0 {
		current.MinRequiredVersionCode = req.MinRequiredVersionCode
	}
	current.ForceUpdate = req.ForceUpdate
	if req.UpdateMode == "immediate" || req.UpdateMode == "flexible" {
		current.UpdateMode = req.UpdateMode
	} else if current.ForceUpdate {
		current.UpdateMode = "immediate"
	} else {
		current.UpdateMode = "flexible"
	}
	if strings.TrimSpace(req.ReleaseNotes) != "" {
		current.ReleaseNotes = strings.TrimSpace(req.ReleaseNotes)
		current.ReleaseNotesI18n["es"] = current.ReleaseNotes
	}
	for k, v := range req.ReleaseNotesI18n {
		if strings.TrimSpace(v) != "" {
			current.ReleaseNotesI18n[k] = strings.TrimSpace(v)
		}
	}
	current.UpdatedAt = time.Now().UTC()

	// Persistir en PostgreSQL si está disponible
	if db := database.GetDB(); db != nil {
		record := models.AppVersionConfig{
			ID:                     "current",
			LatestVersionCode:      current.LatestVersionCode,
			LatestVersionName:      current.LatestVersionName,
			MinRequiredVersionCode: current.MinRequiredVersionCode,
			ForceUpdate:            current.ForceUpdate,
			UpdateMode:             current.UpdateMode,
			ReleaseNotesES:         current.ReleaseNotesI18n["es"],
			ReleaseNotesPT:         current.ReleaseNotesI18n["pt"],
			ReleaseNotesEN:         current.ReleaseNotesI18n["en"],
			ReleaseNotesFR:         current.ReleaseNotesI18n["fr"],
			UpdatedAt:              current.UpdatedAt,
		}
		db.Save(&record)
	}

	versionMutex.Lock()
	runtimeVersion = &current
	versionMutex.Unlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":     true,
		"app_version": current,
	})
}
