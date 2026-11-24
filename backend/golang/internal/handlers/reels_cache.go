package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"backend/internal/config"
	"backend/internal/database"
	"backend/internal/models"

	"github.com/google/uuid"
)

const (
	ReelsFeedCacheTTL        = 20 * time.Second
	ReelsFeedCacheMaxEntries = 200

	ReelMetaCacheTTL        = 5 * time.Minute
	ReelMetaCacheMaxEntries = 5000

	DefaultMaxReelsPerWeekPerCreator = 10   // Protege almacenamiento y Gemini si se supera el ritmo semanal esperado
	DefaultMaxGlobalReelsPerDay      = 2000 // Válvula de seguridad global diaria ante picos virales o ataques
)

// ==============================================================================
// CACHÉ EN MEMORIA PARA FEED DE REELS (REDUCE ~85% DE QUERIES SQL EN HORA PICO)
// ==============================================================================

type cachedFeedEntry struct {
	reels      []models.Reel
	nextCursor string
	expiresAt  time.Time
}

var (
	reelsFeedCacheMu sync.RWMutex
	reelsFeedCache   = make(map[string]cachedFeedEntry)
)

func buildReelsFeedCacheKey(lang, category, gameMode, cursor string, limit int) string {
	return fmt.Sprintf("%s|%s|%s|%s|%d", lang, category, gameMode, cursor, limit)
}

// getCachedFeedPage devuelve una copia segura de los reels cacheados (sin banderas por usuario)
// para evitar fugas de estado (HasLiked/HasSaved/IsFollowing) entre usuarios concurrentes.
func getCachedFeedPage(key string) ([]models.Reel, string, bool) {
	now := time.Now()
	reelsFeedCacheMu.RLock()
	entry, ok := reelsFeedCache[key]
	reelsFeedCacheMu.RUnlock()
	if !ok || now.After(entry.expiresAt) {
		return nil, "", false
	}

	cloned := make([]models.Reel, len(entry.reels))
	copy(cloned, entry.reels)
	return cloned, entry.nextCursor, true
}

func setCachedFeedPage(key string, reels []models.Reel, nextCursor string) {
	now := time.Now()
	snapshot := make([]models.Reel, len(reels))
	for i := range reels {
		r := reels[i]
		r.HasLiked = false
		r.HasSaved = false
		r.IsFollowing = false
		snapshot[i] = r
	}

	reelsFeedCacheMu.Lock()
	defer reelsFeedCacheMu.Unlock()

	if len(reelsFeedCache) >= ReelsFeedCacheMaxEntries {
		for k, v := range reelsFeedCache {
			if now.After(v.expiresAt) {
				delete(reelsFeedCache, k)
			}
		}
		if len(reelsFeedCache) >= ReelsFeedCacheMaxEntries {
			// Evicción rápida si sigue lleno tras limpiar expirados
			reelsFeedCache = make(map[string]cachedFeedEntry, ReelsFeedCacheMaxEntries/2)
		}
	}

	reelsFeedCache[key] = cachedFeedEntry{
		reels:      snapshot,
		nextCursor: nextCursor,
		expiresAt:  now.Add(ReelsFeedCacheTTL),
	}
}

// invalidateReelsFeedCache limpia la caché de feed cuando cambia el catálogo (aprobación, borrado, moderación o recálculo de tendencia).
func invalidateReelsFeedCache() {
	reelsFeedCacheMu.Lock()
	reelsFeedCache = make(map[string]cachedFeedEntry)
	reelsFeedCacheMu.Unlock()
}

// ==============================================================================
// CACHÉ DE METADATOS DE REEL PARA /view/start Y /view (EVITA ~90K SELECT/HORA)
// ==============================================================================

type cachedReelMeta struct {
	creatorID       uuid.UUID
	durationSeconds int
	expiresAt       time.Time
}

var (
	reelMetaCacheMu sync.RWMutex
	reelMetaCache   = make(map[uuid.UUID]cachedReelMeta)
)

func getCachedReelMeta(reelID uuid.UUID) (uuid.UUID, int, bool) {
	now := time.Now()
	reelMetaCacheMu.RLock()
	entry, ok := reelMetaCache[reelID]
	reelMetaCacheMu.RUnlock()
	if !ok || now.After(entry.expiresAt) {
		return uuid.Nil, 0, false
	}
	return entry.creatorID, entry.durationSeconds, true
}

func setCachedReelMeta(reelID, creatorID uuid.UUID, durationSeconds int) {
	now := time.Now()
	reelMetaCacheMu.Lock()
	defer reelMetaCacheMu.Unlock()

	if len(reelMetaCache) >= ReelMetaCacheMaxEntries {
		for k, v := range reelMetaCache {
			if now.After(v.expiresAt) {
				delete(reelMetaCache, k)
			}
		}
		if len(reelMetaCache) >= ReelMetaCacheMaxEntries {
			reelMetaCache = make(map[uuid.UUID]cachedReelMeta, ReelMetaCacheMaxEntries/2)
		}
	}

	reelMetaCache[reelID] = cachedReelMeta{
		creatorID:       creatorID,
		durationSeconds: durationSeconds,
		expiresAt:       now.Add(ReelMetaCacheTTL),
	}
}

func invalidateReelMeta(reelID uuid.UUID) {
	reelMetaCacheMu.Lock()
	delete(reelMetaCache, reelID)
	reelMetaCacheMu.Unlock()
}

// loadActiveReelMeta obtiene creator_id y duration_seconds desde caché o PostgreSQL.
func loadActiveReelMeta(reelID uuid.UUID) (uuid.UUID, int, error) {
	if creatorID, duration, ok := getCachedReelMeta(reelID); ok {
		return creatorID, duration, nil
	}
	var reel models.Reel
	if err := database.DB.Select("id, creator_id, duration_seconds").First(&reel, "id = ? AND active = ?", reelID, true).Error; err != nil {
		return uuid.Nil, 0, err
	}
	setCachedReelMeta(reel.ID, reel.CreatorID, reel.DurationSeconds)
	return reel.CreatorID, reel.DurationSeconds, nil
}

// ==============================================================================
// CUOTAS DE SUBIDA CONFIGURABLES (DIARIA, SEMANAL Y TOPE GLOBAL ANTI-PICOS)
// ==============================================================================

func getEnvIntOrDefault(key string, fallback, minVal int) int {
	raw := strings.TrimSpace(config.GetEnv(key, ""))
	if raw == "" {
		return fallback
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n < minVal {
		return fallback
	}
	return n
}

func getUserDailyReelLimit(user *models.User) int64 {
	dailyLimit := int64(getEnvIntOrDefault("MAX_REELS_PER_DAY_PER_USER", MaxReelsPerDayPerCreator, 1))
	if user != nil && !user.CreatedAt.IsZero() && time.Since(user.CreatedAt) < 24*time.Hour {
		if int64(NewAccountMaxReelsPerDay) < dailyLimit {
			dailyLimit = int64(NewAccountMaxReelsPerDay)
		}
	}
	return dailyLimit
}

func getUserWeeklyReelLimit() int64 {
	return int64(getEnvIntOrDefault("MAX_REELS_PER_WEEK_PER_USER", DefaultMaxReelsPerWeekPerCreator, 0))
}

func getGlobalDailyReelLimit() int64 {
	return int64(getEnvIntOrDefault("MAX_GLOBAL_REELS_PER_DAY", DefaultMaxGlobalReelsPerDay, 0))
}

func countUserReelsLast7DaysUTC(userID uuid.UUID) (int64, error) {
	since := time.Now().UTC().Add(-7 * 24 * time.Hour)
	var count int64
	err := database.DB.Model(&models.Reel{}).
		Where("creator_id = ? AND created_at >= ?", userID, since).
		Count(&count).Error
	return count, err
}

func countGlobalReelsTodayUTC() (int64, error) {
	nowUTC := time.Now().UTC()
	startOfDay := time.Date(nowUTC.Year(), nowUTC.Month(), nowUTC.Day(), 0, 0, 0, 0, time.UTC)
	var count int64
	err := database.DB.Model(&models.Reel{}).
		Where("created_at >= ?", startOfDay).
		Count(&count).Error
	return count, err
}

// checkReelUploadQuotas valida límite diario por usuario, límite semanal por usuario y tope global diario
// ANTES de autorizar URLs prefirmadas a R2 o aceptar archivos.
func checkReelUploadQuotas(user *models.User) (statusCode int, errMsg string) {
	if user == nil || isReelAdmin(user) {
		return 0, ""
	}

	dailyLimit := getUserDailyReelLimit(user)
	todayCount, err := countUserReelsTodayUTC(user.ID)
	if err != nil {
		return http.StatusInternalServerError, "Error verificando límite diario de publicaciones"
	}
	if todayCount >= dailyLimit {
		return http.StatusTooManyRequests, fmt.Sprintf("Has alcanzado el límite de %d video(s) por día. Vuelve mañana.", dailyLimit)
	}

	if weeklyLimit := getUserWeeklyReelLimit(); weeklyLimit > 0 {
		weekCount, errWeek := countUserReelsLast7DaysUTC(user.ID)
		if errWeek == nil && weekCount >= weeklyLimit {
			return http.StatusTooManyRequests, fmt.Sprintf("Has alcanzado el límite semanal de %d videos. Podrás subir más en unos días.", weeklyLimit)
		}
	}

	if globalLimit := getGlobalDailyReelLimit(); globalLimit > 0 {
		globalToday, errGlobal := countGlobalReelsTodayUTC()
		if errGlobal == nil && globalToday >= globalLimit {
			return http.StatusServiceUnavailable, "Estamos recibiendo muchísimos videos hoy. Intenta subir tu Brief nuevamente mañana."
		}
	}

	return 0, ""
}
