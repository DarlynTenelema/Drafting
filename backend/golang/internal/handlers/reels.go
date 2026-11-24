package handlers

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"backend/internal/config"
	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
	"backend/internal/storage"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

const (
	MaxReelUploadBytes       = 15 << 20 // 15 MB máximo para videos 720p comprimidos (10-30s)
	MinReelDurationSeconds   = 10
	MaxReelDurationSeconds   = 30
	MaxReelsPerDayPerCreator = 2
	MinVerifiedWatchPercent  = 90
	MinReportsToAutoSilence  = 10
	ReportSilenceRatioMin    = 0.02 // 2% de las vistas para evitar brigading en videos virales
	ReportLowViewsThreshold  = 500
	CreatorPayoutPerViewUSD  = 0.00001 // $0.01 por cada 1,000 vistas verificadas ($10 por millón)
	MinCreatorPayoutUSD      = 100.0   // Mínimo $100 USD para solicitar retiro en efectivo
)

// detectVideoOrientation determina si el video es horizontal ('landscape') o vertical ('portrait').
func detectVideoOrientation(width, height int, requested string) string {
	if width > 0 && height > 0 {
		if float64(width) > float64(height)*1.05 {
			return "landscape"
		}
		return "portrait"
	}
	if strings.EqualFold(strings.TrimSpace(requested), "landscape") {
		return "landscape"
	}
	return "portrait"
}

// encodeFeedCursor codifica un cursor compuesto (trend_score, created_at, id) para paginación estable.
func encodeFeedCursor(score float64, createdAt time.Time, id uuid.UUID) string {
	raw := fmt.Sprintf("%.8f|%s|%s", score, createdAt.UTC().Format(time.RFC3339Nano), id.String())
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

func decodeFeedCursor(cursor string) (score float64, createdAt time.Time, id uuid.UUID, isComposite bool, ok bool) {
	trimmed := strings.TrimSpace(cursor)
	if trimmed == "" {
		return 0, time.Time{}, uuid.Nil, false, false
	}
	if decoded, err := base64.RawURLEncoding.DecodeString(trimmed); err == nil {
		parts := strings.Split(string(decoded), "|")
		if len(parts) == 3 {
			s, errS := strconv.ParseFloat(parts[0], 64)
			t, errT := time.Parse(time.RFC3339Nano, parts[1])
			uid, errU := uuid.Parse(parts[2])
			if errS == nil && errT == nil && errU == nil {
				return s, t, uid, true, true
			}
		}
	}
	// Retrocompatibilidad con cursor antiguo de timestamp simple
	if t, err := time.Parse(time.RFC3339Nano, trimmed); err == nil {
		return 0, t, uuid.Nil, false, true
	}
	return 0, time.Time{}, uuid.Nil, false, false
}

func hashClientIP(r *http.Request) string {
	ip := ""
	if xff := strings.TrimSpace(r.Header.Get("X-Forwarded-For")); xff != "" {
		if idx := strings.Index(xff, ","); idx != -1 {
			ip = strings.TrimSpace(xff[:idx])
		} else {
			ip = xff
		}
	} else if xri := strings.TrimSpace(r.Header.Get("X-Real-IP")); xri != "" {
		ip = xri
	} else if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		ip = host
	} else {
		ip = r.RemoteAddr
	}
	if ip == "" {
		return ""
	}
	salt := config.GetEnv("JWT_SECRET", "drafting-ip-salt")
	sum := sha256.Sum256([]byte(salt + ":" + ip))
	return hex.EncodeToString(sum[:])
}

func cleanupReelStorageFiles(reel *models.Reel) {
	if storage.Instance == nil || reel == nil {
		return
	}
	videoKey := strings.TrimSpace(reel.VideoKey)
	thumbKey := strings.TrimSpace(reel.ThumbnailURL)
	go func() {
		if videoKey != "" {
			if err := storage.Instance.DeleteObject(videoKey); err != nil {
				log.Printf("[Reels] Error eliminando video %s de storage: %v", videoKey, err)
			}
		}
		if thumbKey != "" && !strings.HasPrefix(strings.ToLower(thumbKey), "http") {
			_ = storage.Instance.DeleteObject(thumbKey)
		}
	}()
}

// Helper para parsear usuario autenticado opcional (para endpoints públicos que muestran likes/saves si hay token)
func getOptionalUser(r *http.Request) *models.User {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if ok && user != nil {
		return user
	}
	return nil
}

func isReelAdmin(user *models.User) bool {
	return user != nil && strings.EqualFold(strings.TrimSpace(user.Email), AuthorizedAdminEmail)
}

// resolveReelMediaURLs normaliza las URLs de video usando MEDIA_PUBLIC_URL si existe video_key (portabilidad Bare Metal/S3)
func resolveReelMediaURLs(reel *models.Reel) {
	if storage.Instance == nil {
		return
	}
	if strings.TrimSpace(reel.VideoKey) != "" {
		reel.VideoURL = storage.Instance.PublicURLForKey(reel.VideoKey)
	}
	if strings.TrimSpace(reel.ThumbnailURL) != "" && !strings.HasPrefix(strings.ToLower(reel.ThumbnailURL), "http") {
		reel.ThumbnailURL = storage.Instance.PublicURLForKey(reel.ThumbnailURL)
	}
}

func countUserReelsTodayUTC(userID uuid.UUID) (int64, error) {
	nowUTC := time.Now().UTC()
	startOfDay := time.Date(nowUTC.Year(), nowUTC.Month(), nowUTC.Day(), 0, 0, 0, 0, time.UTC)
	var count int64
	err := database.DB.Model(&models.Reel{}).
		Where("creator_id = ? AND created_at >= ?", userID, startOfDay).
		Count(&count).Error
	return count, err
}

// StartReelsTrendWorker recalcula trend_score en lote cada 5 minutos en 1 sola consulta SQL.
// Evita lanzar miles de goroutines/queries por vista al escalar a millones de usuarios.
func StartReelsTrendWorker() {
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()

		recalc := func() {
			if database.DB == nil {
				return
			}
			// Fórmula de tendencia: pondera likes (x3), vistas verificadas (x2) y vistas totales (x1) con decaimiento temporal
			sql := `
				UPDATE reels
				SET trend_score = (
					(COALESCE(likes_count, 0) * 3.0 + COALESCE(verified_views_count, 0) * 2.0 + COALESCE(views_count, 0) + 10.0)
					/ POWER(GREATEST(EXTRACT(EPOCH FROM (NOW() - created_at)) / 3600.0, 0.0) + 2.0, 1.4)
				)
				WHERE active = TRUE
				  AND deleted_at IS NULL
				  AND created_at >= NOW() - INTERVAL '30 days'
			`
			if err := database.DB.Exec(sql).Error; err != nil {
				log.Printf("[ReelsTrendWorker] Error recalculando trend_score: %v", err)
			} else {
				invalidateReelsFeedCache()
			}
		}

		// Primera ejecución al arrancar (con pequeño retraso para no competir con el boot)
		time.Sleep(10 * time.Second)
		recalc()

		for range ticker.C {
			recalc()
		}
	}()
}

// GetReelsFeed entrega el feed de reels filtrado por idioma, categoría y paginado
func GetReelsFeed(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	lang := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("lang")))
	category := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("category")))
	gameMode := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("game_mode")))
	cursorStr := r.URL.Query().Get("cursor")
	limitStr := r.URL.Query().Get("limit")

	limit := 10
	if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= 30 {
		limit = l
	}

	currentUser := getOptionalUser(r)
	blockedIDs := getBlockedUserIDsForViewer(currentUser)
	cacheKey := buildReelsFeedCacheKey(lang, category, gameMode, cursorStr, limit)

	var reels []models.Reel
	var nextCursor string
	fromCache := false

	// Usar caché compartida de 20s cuando el usuario no tiene creadores bloqueados (99% del tráfico en hora pico)
	if len(blockedIDs) == 0 {
		if cachedReels, cachedCursor, ok := getCachedFeedPage(cacheKey); ok {
			reels = cachedReels
			nextCursor = cachedCursor
			fromCache = true
		}
	}

	if !fromCache {
		query := database.DB.Model(&models.Reel{}).
			Where("active = ?", true).
			Preload("Creator")

		// Ocultar inmediatamente videos de creadores bloqueados por el usuario (requisito Play Store / App Store UGC)
		if len(blockedIDs) > 0 {
			query = query.Where("creator_id NOT IN ?", blockedIDs)
		}

		if lang != "" && lang != "all" {
			query = query.Where("language = ? OR language = 'universal'", lang)
		}

		if category != "" && category != "todos" && category != "all" {
			query = query.Where("LOWER(category) = ?", category)
		}

		if gameMode != "" && gameMode != "todos" && gameMode != "all" {
			query = query.Where("LOWER(game_mode) = ?", gameMode)
		}

		if cursorStr != "" {
			if cScore, cTime, cID, isComp, ok := decodeFeedCursor(cursorStr); ok {
				if isComp {
					query = query.Where(
						"(trend_score < ?) OR (trend_score = ? AND created_at < ?) OR (trend_score = ? AND created_at = ? AND id < ?)",
						cScore, cScore, cTime, cScore, cTime, cID,
					)
				} else {
					query = query.Where("created_at < ?", cTime)
				}
			}
		}

		if err := query.Order("trend_score DESC, created_at DESC, id DESC").Limit(limit).Find(&reels).Error; err != nil {
			http.Error(w, `{"error":"Error al consultar el feed de reels"}`, http.StatusInternalServerError)
			return
		}

		if len(reels) > 0 {
			creatorIDSet := make(map[uuid.UUID]struct{})
			creatorIDs := make([]uuid.UUID, 0, len(reels))
			for _, reel := range reels {
				if _, exists := creatorIDSet[reel.CreatorID]; !exists {
					creatorIDSet[reel.CreatorID] = struct{}{}
					creatorIDs = append(creatorIDs, reel.CreatorID)
				}
			}

			// Conteo de seguidores reales por creador en una sola consulta agrupada
			type followAgg struct {
				FollowingID uuid.UUID
				Cnt         int64
			}
			var followCounts []followAgg
			database.DB.Model(&models.UserFollow{}).
				Select("following_id, COUNT(*) as cnt").
				Where("following_id IN ?", creatorIDs).
				Group("following_id").
				Scan(&followCounts)
			followersMap := make(map[uuid.UUID]int64, len(followCounts))
			for _, fc := range followCounts {
				followersMap[fc.FollowingID] = fc.Cnt
			}

			for i := range reels {
				resolveReelMediaURLs(&reels[i])
				reels[i].CreatorUsername = reels[i].Creator.Username
				reels[i].CreatorAvatar = reels[i].Creator.ProfilePic
				reels[i].CreatorFollowersCount = followersMap[reels[i].CreatorID]
				if reels[i].Orientation == "" {
					reels[i].Orientation = detectVideoOrientation(reels[i].Width, reels[i].Height, "")
				}
				setCachedReelMeta(reels[i].ID, reels[i].CreatorID, reels[i].DurationSeconds)
			}

			last := reels[len(reels)-1]
			nextCursor = encodeFeedCursor(last.TrendScore, last.CreatedAt, last.ID)
		}

		if len(blockedIDs) == 0 {
			setCachedFeedPage(cacheKey, reels, nextCursor)
		}
	}

	if len(reels) > 0 && currentUser != nil {
		reelIDs := make([]uuid.UUID, len(reels))
		creatorIDSet := make(map[uuid.UUID]struct{})
		creatorIDs := make([]uuid.UUID, 0, len(reels))
		for i, reel := range reels {
			reelIDs[i] = reel.ID
			if _, exists := creatorIDSet[reel.CreatorID]; !exists {
				creatorIDSet[reel.CreatorID] = struct{}{}
				creatorIDs = append(creatorIDs, reel.CreatorID)
			}
		}

		likedMap := make(map[uuid.UUID]bool)
		savedMap := make(map[uuid.UUID]bool)
		followingMap := make(map[uuid.UUID]bool)

		var likedIDs []uuid.UUID
		database.DB.Model(&models.ReelLike{}).
			Where("user_id = ? AND reel_id IN ?", currentUser.ID, reelIDs).
			Pluck("reel_id", &likedIDs)
		for _, id := range likedIDs {
			likedMap[id] = true
		}

		var savedIDs []uuid.UUID
		database.DB.Model(&models.ReelSave{}).
			Where("user_id = ? AND reel_id IN ?", currentUser.ID, reelIDs).
			Pluck("reel_id", &savedIDs)
		for _, id := range savedIDs {
			savedMap[id] = true
		}

		var followedCreatorIDs []uuid.UUID
		database.DB.Model(&models.UserFollow{}).
			Where("follower_id = ? AND following_id IN ?", currentUser.ID, creatorIDs).
			Pluck("following_id", &followedCreatorIDs)
		for _, cid := range followedCreatorIDs {
			followingMap[cid] = true
		}

		for i := range reels {
			reels[i].HasLiked = likedMap[reels[i].ID]
			reels[i].HasSaved = savedMap[reels[i].ID]
			reels[i].IsFollowing = followingMap[reels[i].CreatorID]
		}
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"reels":       reels,
		"next_cursor": nextCursor,
		"count":       len(reels),
	})
}

// GetReelByID obtiene el detalle de un reel específico
func GetReelByID(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	idStr := chi.URLParam(r, "id")
	reelID, err := uuid.Parse(idStr)
	if err != nil {
		http.Error(w, `{"error":"ID de reel inválido"}`, http.StatusBadRequest)
		return
	}

	var reel models.Reel
	if err := database.DB.Preload("Creator").First(&reel, "id = ? AND active = ?", reelID, true).Error; err != nil {
		http.Error(w, `{"error":"Reel no encontrado"}`, http.StatusNotFound)
		return
	}

	resolveReelMediaURLs(&reel)

	var followersCount int64
	database.DB.Model(&models.UserFollow{}).Where("following_id = ?", reel.CreatorID).Count(&followersCount)
	reel.CreatorFollowersCount = followersCount

	currentUser := getOptionalUser(r)
	if currentUser != nil {
		var likeCount int64
		database.DB.Model(&models.ReelLike{}).Where("reel_id = ? AND user_id = ?", reel.ID, currentUser.ID).Count(&likeCount)
		reel.HasLiked = likeCount > 0

		var saveCount int64
		database.DB.Model(&models.ReelSave{}).Where("reel_id = ? AND user_id = ?", reel.ID, currentUser.ID).Count(&saveCount)
		reel.HasSaved = saveCount > 0

		var followCount int64
		database.DB.Model(&models.UserFollow{}).Where("follower_id = ? AND following_id = ?", currentUser.ID, reel.CreatorID).Count(&followCount)
		reel.IsFollowing = followCount > 0
	}
	reel.CreatorUsername = reel.Creator.Username
	reel.CreatorAvatar = reel.Creator.ProfilePic
	if reel.Orientation == "" {
		reel.Orientation = detectVideoOrientation(reel.Width, reel.Height, "")
	}

	_ = json.NewEncoder(w).Encode(reel)
}

// PresignUploadRequest solicita una URL prefirmada para subir directo a Cloudflare R2 / S3 sin pasar por RAM del servidor
type PresignUploadRequest struct {
	Filename        string `json:"filename"`
	ContentType     string `json:"content_type"`
	FileSizeBytes   int64  `json:"file_size_bytes"`
	DurationSeconds int    `json:"duration_seconds"`
	IncludeThumb    bool   `json:"include_thumb"`
}

// PresignReelUpload valida límites (2 videos/día, 10-30s, <=15MB) y entrega URL PUT prefirmada si Object Storage está activo
func PresignReelUpload(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	var req PresignUploadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Cuerpo de petición inválido"}`, http.StatusBadRequest)
		return
	}

	if req.FileSizeBytes > MaxReelUploadBytes {
		http.Error(w, `{"error":"El video comprimido excede el límite máximo permitido (15 MB)"}`, http.StatusBadRequest)
		return
	}

	if req.DurationSeconds > 0 && (req.DurationSeconds < MinReelDurationSeconds || req.DurationSeconds > MaxReelDurationSeconds) {
		http.Error(w, `{"error":"El video debe durar obligatoriamente entre 10 y 30 segundos"}`, http.StatusBadRequest)
		return
	}

	if statusCode, errMsg := checkReelUploadQuotas(user); statusCode != 0 {
		http.Error(w, fmt.Sprintf(`{"error":%q}`, errMsg), statusCode)
		return
	}

	if storage.Instance == nil || !storage.Instance.IsObjectStorageConfigured() {
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"use_direct_upload": false,
			"max_size_bytes":    MaxReelUploadBytes,
		})
		return
	}

	filename := strings.TrimSpace(req.Filename)
	if filename == "" {
		filename = "reel.mp4"
	}
	contentType := strings.TrimSpace(req.ContentType)
	if contentType == "" {
		contentType = "video/mp4"
	}

	videoPresign, err := storage.Instance.GeneratePresignedUploadURL("reels", filename, contentType, 10*time.Minute)
	if err != nil {
		http.Error(w, `{"error":"No se pudo generar URL de subida directa"}`, http.StatusInternalServerError)
		return
	}

	resp := map[string]interface{}{
		"use_direct_upload": true,
		"max_size_bytes":    MaxReelUploadBytes,
		"video":             videoPresign,
	}

	if req.IncludeThumb {
		thumbPresign, errThumb := storage.Instance.GeneratePresignedUploadURL("thumbnails", "thumb.jpg", "image/jpeg", 10*time.Minute)
		if errThumb == nil {
			resp["thumbnail"] = thumbPresign
		}
	}

	_ = json.NewEncoder(w).Encode(resp)
}

// UploadReelMedia recibe archivos multimedia multipart (fallback cuando no se usa subida directa prefirmada)
func UploadReelMedia(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	if statusCode, errMsg := checkReelUploadQuotas(user); statusCode != 0 {
		http.Error(w, fmt.Sprintf(`{"error":%q}`, errMsg), statusCode)
		return
	}

	// Límite estricto de 15 MB para videos 720p comprimidos de 10-30s (+2 MB margen para thumbnail/headers)
	r.Body = http.MaxBytesReader(w, r.Body, MaxReelUploadBytes+(2<<20))
	if err := r.ParseMultipartForm(MaxReelUploadBytes + (2 << 20)); err != nil {
		http.Error(w, `{"error":"El archivo excede el tamaño máximo permitido (15 MB). Comprime el video a 720p."}`, http.StatusBadRequest)
		return
	}

	videoFile, videoHeader, err := r.FormFile("video")
	if err != nil {
		http.Error(w, `{"error":"El archivo de video es requerido"}`, http.StatusBadRequest)
		return
	}
	defer videoFile.Close()

	if videoHeader.Size > MaxReelUploadBytes {
		http.Error(w, `{"error":"El video excede los 15 MB máximos permitidos"}`, http.StatusBadRequest)
		return
	}

	videoURL, videoKey, err := storage.Instance.UploadMedia(videoFile, videoHeader.Filename, videoHeader.Header.Get("Content-Type"))
	if err != nil {
		http.Error(w, fmt.Sprintf(`{"error":"Fallo al subir video: %s"}`, err.Error()), http.StatusInternalServerError)
		return
	}

	thumbnailURL := ""
	thumbFile, thumbHeader, err := r.FormFile("thumbnail")
	if err == nil && thumbHeader != nil {
		defer thumbFile.Close()
		tURL, _, errUpload := storage.Instance.UploadMedia(thumbFile, thumbHeader.Filename, thumbHeader.Header.Get("Content-Type"))
		if errUpload == nil {
			thumbnailURL = tURL
		}
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"video_url":       videoURL,
		"video_key":       videoKey,
		"thumbnail_url":   thumbnailURL,
		"file_size_bytes": videoHeader.Size,
	})
}

// CreateReelRequest estructura para crear un reel
type CreateReelRequest struct {
	Title           string   `json:"title"`
	Description     string   `json:"description"`
	Tags            []string `json:"tags"`
	VideoURL        string   `json:"video_url"`
	VideoKey        string   `json:"video_key"`
	ThumbnailURL    string   `json:"thumbnail_url"`
	DurationSeconds int      `json:"duration_seconds"`
	FileSizeBytes   int64    `json:"file_size_bytes"`
	Width           int      `json:"width"`
	Height          int      `json:"height"`
	Orientation     string   `json:"orientation"`
	GameMode        string   `json:"game_mode"`
	Category        string   `json:"category"`
	Language        string   `json:"language"`
	ChampionName    string   `json:"champion_name"`
}

// CreateReel registra un nuevo reel aplicando reglas obligatorias: 10-30s y máx. 2 videos/día por creador
func CreateReel(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	var req CreateReelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Cuerpo de petición inválido"}`, http.StatusBadRequest)
		return
	}

	req.Title = strings.TrimSpace(req.Title)
	if len(req.Title) < 3 || len(req.Title) > 180 {
		http.Error(w, `{"error":"El título debe tener entre 3 y 180 caracteres"}`, http.StatusBadRequest)
		return
	}

	req.VideoURL = strings.TrimSpace(req.VideoURL)
	req.VideoKey = strings.TrimSpace(req.VideoKey)
	if req.VideoURL == "" && req.VideoKey != "" && storage.Instance != nil {
		req.VideoURL = storage.Instance.PublicURLForKey(req.VideoKey)
	}
	if req.VideoURL == "" {
		http.Error(w, `{"error":"La URL del video es requerida"}`, http.StatusBadRequest)
		return
	}

	// Regla obligatoria: duración estricta entre 10 y 30 segundos
	if req.DurationSeconds < MinReelDurationSeconds || req.DurationSeconds > MaxReelDurationSeconds {
		http.Error(w, `{"error":"El video debe durar entre 10 y 30 segundos"}`, http.StatusBadRequest)
		return
	}

	if req.FileSizeBytes > MaxReelUploadBytes {
		http.Error(w, `{"error":"El video excede el límite máximo de 15 MB"}`, http.StatusBadRequest)
		return
	}

	// Regla obligatoria: cuotas diaria, semanal y tope global anti-picos
	if statusCode, errMsg := checkReelUploadQuotas(user); statusCode != 0 {
		http.Error(w, fmt.Sprintf(`{"error":%q}`, errMsg), statusCode)
		return
	}

	lang := strings.ToLower(strings.TrimSpace(req.Language))
	if lang == "" || (lang != "es" && lang != "en" && lang != "fr" && lang != "pt" && lang != "universal") {
		lang = "universal"
	}

	cat := strings.ToLower(strings.TrimSpace(req.Category))
	if cat == "" {
		cat = "jugadas"
	}

	mode := strings.ToLower(strings.TrimSpace(req.GameMode))
	if mode != "lol_pc" {
		mode = "wild_rift"
	}

	desc := strings.TrimSpace(req.Description)
	if desc == "" && len(req.Tags) > 0 {
		cleanTags := make([]string, 0, len(req.Tags))
		for _, t := range req.Tags {
			ct := strings.TrimSpace(strings.TrimPrefix(strings.ToLower(t), "#"))
			if ct != "" {
				cleanTags = append(cleanTags, "#"+ct)
			}
		}
		desc = strings.Join(cleanTags, " ")
	}
	orientation := detectVideoOrientation(req.Width, req.Height, req.Orientation)

	isAdmin := isReelAdmin(user)
	initialActive := isAdmin
	initialModStatus := ModerationStatusPendingScan
	if isAdmin {
		initialModStatus = ModerationStatusApproved
	}

	reel := models.Reel{
		CreatorID:        user.ID,
		Title:            req.Title,
		Description:      desc,
		VideoURL:         req.VideoURL,
		VideoKey:         req.VideoKey,
		ThumbnailURL:     strings.TrimSpace(req.ThumbnailURL),
		DurationSeconds:  req.DurationSeconds,
		FileSizeBytes:    req.FileSizeBytes,
		Width:            req.Width,
		Height:           req.Height,
		Orientation:      orientation,
		GameMode:         mode,
		Category:         cat,
		Language:         lang,
		ChampionName:     strings.TrimSpace(req.ChampionName),
		TrendScore:       10.0, // Impulso inicial para aparecer en el feed
		Active:           initialActive,
		ModerationStatus: initialModStatus,
	}

	if err := database.DB.Create(&reel).Error; err != nil {
		http.Error(w, `{"error":"Error al guardar el reel en la base de datos"}`, http.StatusInternalServerError)
		return
	}

	// Escaneo proactivo asíncrono de fotogramas + dHash + Gemini Flash antes de aparecer en el feed público
	if !isAdmin {
		RunProactiveReelModeration(reel.ID)
	} else {
		invalidateReelsFeedCache()
	}

	resolveReelMediaURLs(&reel)
	reel.CreatorUsername = user.Username
	reel.CreatorAvatar = user.ProfilePic

	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(reel)
}

// ToggleLikeReel añade o quita el me gusta atómicamente
func ToggleLikeReel(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	reelID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"ID de reel inválido"}`, http.StatusBadRequest)
		return
	}

	var liked bool
	var currentLikes int

	err = database.DB.Transaction(func(tx *gorm.DB) error {
		var existingLike models.ReelLike
		errFind := tx.Where("reel_id = ? AND user_id = ?", reelID, user.ID).First(&existingLike).Error

		if errFind == nil {
			if errDel := tx.Delete(&existingLike).Error; errDel != nil {
				return errDel
			}
			if errUpd := tx.Model(&models.Reel{}).Where("id = ?", reelID).
				Update("likes_count", gorm.Expr("GREATEST(0, likes_count - 1)")).Error; errUpd != nil {
				return errUpd
			}
			liked = false
		} else {
			newLike := models.ReelLike{ReelID: reelID, UserID: user.ID}
			if errIns := tx.Create(&newLike).Error; errIns != nil {
				return errIns
			}
			if errUpd := tx.Model(&models.Reel{}).Where("id = ?", reelID).
				Update("likes_count", gorm.Expr("likes_count + 1")).Error; errUpd != nil {
				return errUpd
			}
			liked = true
		}

		var updatedReel models.Reel
		if errGet := tx.Select("likes_count").First(&updatedReel, "id = ?", reelID).Error; errGet != nil {
			return errGet
		}
		currentLikes = updatedReel.LikesCount
		return nil
	})

	if err != nil {
		http.Error(w, `{"error":"Error al procesar el like"}`, http.StatusInternalServerError)
		return
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"liked":       liked,
		"likes_count": currentLikes,
	})
}

// ToggleSaveReel añade o quita un reel de guardados/favoritos
func ToggleSaveReel(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	reelID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"ID de reel inválido"}`, http.StatusBadRequest)
		return
	}

	var saved bool
	var currentSaves int

	err = database.DB.Transaction(func(tx *gorm.DB) error {
		var existingSave models.ReelSave
		errFind := tx.Where("reel_id = ? AND user_id = ?", reelID, user.ID).First(&existingSave).Error

		if errFind == nil {
			if errDel := tx.Delete(&existingSave).Error; errDel != nil {
				return errDel
			}
			if errUpd := tx.Model(&models.Reel{}).Where("id = ?", reelID).
				Update("saves_count", gorm.Expr("GREATEST(0, saves_count - 1)")).Error; errUpd != nil {
				return errUpd
			}
			saved = false
		} else {
			newSave := models.ReelSave{ReelID: reelID, UserID: user.ID}
			if errIns := tx.Create(&newSave).Error; errIns != nil {
				return errIns
			}
			if errUpd := tx.Model(&models.Reel{}).Where("id = ?", reelID).
				Update("saves_count", gorm.Expr("saves_count + 1")).Error; errUpd != nil {
				return errUpd
			}
			saved = true
		}

		var updatedReel models.Reel
		if errGet := tx.Select("saves_count").First(&updatedReel, "id = ?", reelID).Error; errGet != nil {
			return errGet
		}
		currentSaves = updatedReel.SavesCount
		return nil
	})

	if err != nil {
		http.Error(w, `{"error":"Error al procesar el guardado"}`, http.StatusInternalServerError)
		return
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"saved":       saved,
		"saves_count": currentSaves,
	})
}

// ==============================================================================
// VISTAS VERIFICADAS ANTI-BOT (TOKEN FIRMADO + >=90% VISTO + 1 VISTA ÚNICA/USUARIO)
// ==============================================================================

type viewTokenPayload struct {
	ReelID          string `json:"r"`
	UserID          string `json:"u"`
	DurationSeconds int    `json:"d"`
	StartedAt       int64  `json:"t"`
}

func viewTokenSecret() []byte {
	secret := config.GetEnv("JWT_SECRET", "drafting-dev-view-secret")
	return []byte("reel-view-v1:" + secret)
}

func signViewToken(p viewTokenPayload) (string, error) {
	raw, err := json.Marshal(p)
	if err != nil {
		return "", err
	}
	encoded := base64.RawURLEncoding.EncodeToString(raw)
	mac := hmac.New(sha256.New, viewTokenSecret())
	mac.Write([]byte(encoded))
	sig := hex.EncodeToString(mac.Sum(nil))
	return encoded + "." + sig, nil
}

func verifyViewToken(token string) (*viewTokenPayload, bool) {
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return nil, false
	}
	mac := hmac.New(sha256.New, viewTokenSecret())
	mac.Write([]byte(parts[0]))
	expectedSig := hex.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(parts[1]), []byte(expectedSig)) {
		return nil, false
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, false
	}
	var p viewTokenPayload
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, false
	}
	return &p, true
}

// StartReelViewSession emite un token firmado con timestamp real del servidor al iniciar la reproducción.
func StartReelViewSession(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	reelID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"ID de reel inválido"}`, http.StatusBadRequest)
		return
	}

	_, duration, err := loadActiveReelMeta(reelID)
	if err != nil {
		http.Error(w, `{"error":"Reel no encontrado"}`, http.StatusNotFound)
		return
	}

	if duration < MinReelDurationSeconds {
		duration = MinReelDurationSeconds
	}

	userIDStr := ""
	if currentUser := getOptionalUser(r); currentUser != nil {
		userIDStr = currentUser.ID.String()
	}

	token, err := signViewToken(viewTokenPayload{
		ReelID:          reelID.String(),
		UserID:          userIDStr,
		DurationSeconds: duration,
		StartedAt:       time.Now().UTC().Unix(),
	})
	if err != nil {
		http.Error(w, `{"error":"No se pudo iniciar la sesión de reproducción"}`, http.StatusInternalServerError)
		return
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"view_token":       token,
		"duration_seconds": duration,
		"min_percent":      MinVerifiedWatchPercent,
	})
}

type RecordReelViewRequest struct {
	ViewToken      string `json:"view_token"`
	WatchedSeconds int    `json:"watched_seconds"`
	WatchedPercent int    `json:"watched_percent"`
}

// RecordReelView registra una vista única por usuario y valida si califica como vista verificada (>=90% real).
func RecordReelView(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	reelID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"ID de reel inválido"}`, http.StatusBadRequest)
		return
	}

	var req RecordReelViewRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}

	creatorID, duration, err := loadActiveReelMeta(reelID)
	if err != nil {
		http.Error(w, `{"error":"Reel no encontrado"}`, http.StatusNotFound)
		return
	}
	reel := models.Reel{ID: reelID, CreatorID: creatorID, DurationSeconds: duration}

	currentUser := getOptionalUser(r)
	if currentUser == nil {
		// Usuarios anónimos no generan vistas verificadas ni monetizables (anti-bots)
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"status":   "ignored_anonymous",
			"verified": false,
		})
		return
	}

	if duration < MinReelDurationSeconds {
		duration = MinReelDurationSeconds
	}

	// Evaluar si cumple criterios de vista verificada:
	// 1. No es el propio creador (anti self-farming)
	// 2. Token firmado válido emitido por /view/start para este reel y usuario
	// 3. Tiempo real transcurrido en el servidor >= 85% de la duración (tolerancia de 5% por latencia de red)
	// 4. Porcentaje reportado >= 90% y segundos vistos >= 90% de duración
	isVerified := false
	if currentUser.ID != reel.CreatorID && req.ViewToken != "" && req.WatchedPercent >= MinVerifiedWatchPercent {
		if payload, ok := verifyViewToken(req.ViewToken); ok {
			elapsed := time.Now().UTC().Unix() - payload.StartedAt
			minServerSeconds := int64(math.Floor(float64(duration) * 0.85))
			minWatchedSeconds := int(math.Floor(float64(duration) * 0.90))

			if payload.ReelID == reelID.String() &&
				payload.UserID == currentUser.ID.String() &&
				elapsed >= minServerSeconds &&
				elapsed <= 600 && // ventana máxima de 10 minutos para evitar tokens reutilizados viejos
				req.WatchedSeconds >= minWatchedSeconds {
				isVerified = true
			}
		}
	}

	ipHash := hashClientIP(r)
	deviceID := strings.TrimSpace(currentUser.DeviceID)

	// Anti-granja: impedir que varias cuentas en el mismo dispositivo o IP generen vistas verificadas del mismo video
	if isVerified {
		var dupCount int64
		if deviceID != "" {
			database.DB.Model(&models.ReelView{}).
				Where("reel_id = ? AND device_id = ? AND verified = ? AND (user_id IS NULL OR user_id <> ?)", reelID, deviceID, true, currentUser.ID).
				Count(&dupCount)
		}
		if dupCount == 0 && ipHash != "" {
			database.DB.Model(&models.ReelView{}).
				Where("reel_id = ? AND ip_hash = ? AND verified = ? AND (user_id IS NULL OR user_id <> ?)", reelID, ipHash, true, currentUser.ID).
				Count(&dupCount)
		}
		if dupCount > 0 {
			isVerified = false
		}
	}

	// Garantizar estrictamente 1 vista única por usuario por video usando ON CONFLICT DO NOTHING
	viewEntry := models.ReelView{
		ReelID:         reelID,
		UserID:         &currentUser.ID,
		IPHash:         ipHash,
		DeviceID:       deviceID,
		WatchedSeconds: req.WatchedSeconds,
		WatchedPercent: req.WatchedPercent,
		Verified:       isVerified,
	}

	counted := false
	verifiedCounted := false

	err = database.DB.Transaction(func(tx *gorm.DB) error {
		res := tx.Clauses(clause.OnConflict{
			Columns:     []clause.Column{{Name: "reel_id"}, {Name: "user_id"}},
			TargetWhere: clause.Where{Exprs: []clause.Expression{clause.Expr{SQL: "user_id IS NOT NULL"}}},
			DoNothing:   true,
		}).Create(&viewEntry)
		if res.Error != nil {
			return res.Error
		}

		if res.RowsAffected > 0 {
			counted = true
			updates := map[string]interface{}{
				"views_count": gorm.Expr("views_count + 1"),
			}
			if isVerified {
				verifiedCounted = true
				updates["verified_views_count"] = gorm.Expr("verified_views_count + 1")
			}
			if err := tx.Model(&models.Reel{}).Where("id = ?", reelID).Updates(updates).Error; err != nil {
				return err
			}
			if isVerified {
				return tx.Model(&models.User{}).Where("id = ?", reel.CreatorID).
					Update("lifetime_verified_views", gorm.Expr("COALESCE(lifetime_verified_views, 0) + 1")).Error
			}
			return nil
		}

		// Si ya existía una vista no verificada de este usuario y ahora completó el 90%, promoverla una sola vez
		if isVerified {
			upd := tx.Model(&models.ReelView{}).
				Where("reel_id = ? AND user_id = ? AND verified = ?", reelID, currentUser.ID, false).
				Updates(map[string]interface{}{
					"verified":        true,
					"ip_hash":         ipHash,
					"device_id":       deviceID,
					"watched_seconds": req.WatchedSeconds,
					"watched_percent": req.WatchedPercent,
				})
			if upd.Error != nil {
				return upd.Error
			}
			if upd.RowsAffected > 0 {
				verifiedCounted = true
				if err := tx.Model(&models.Reel{}).Where("id = ?", reelID).
					Update("verified_views_count", gorm.Expr("verified_views_count + 1")).Error; err != nil {
					return err
				}
				return tx.Model(&models.User{}).Where("id = ?", reel.CreatorID).
					Update("lifetime_verified_views", gorm.Expr("COALESCE(lifetime_verified_views, 0) + 1")).Error
			}
		}

		return nil
	})

	if err != nil {
		http.Error(w, `{"error":"Error al registrar la visualización"}`, http.StatusInternalServerError)
		return
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":           "ok",
		"unique_counted":   counted,
		"verified_counted": verifiedCounted,
	})
}

// ==============================================================================
// SISTEMA DE REPORTES COMUNITARIOS (ANTI-BRIGADING) Y PANEL ADMIN
// ==============================================================================

type ReportReelRequest struct {
	Reason  string `json:"reason"`
	Details string `json:"details"`
}

// ReportReel permite reportar un video. A los 10 reportes (y >=2% de vistas en videos virales)
// silencia el video automáticamente y lo deja en cola para revisión en el panel admin.
func ReportReel(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	reelID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"ID de reel inválido"}`, http.StatusBadRequest)
		return
	}

	var req ReportReelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Cuerpo de petición inválido"}`, http.StatusBadRequest)
		return
	}

	reason := normalizeReportReason(req.Reason)

	details := strings.TrimSpace(req.Details)
	if len(details) > 300 {
		details = details[:300]
	}

	var reel models.Reel
	if err := database.DB.First(&reel, "id = ?", reelID).Error; err != nil {
		http.Error(w, `{"error":"Reel no encontrado"}`, http.StatusNotFound)
		return
	}

	if reel.CreatorID == user.ID {
		http.Error(w, `{"error":"No puedes reportar tu propio video"}`, http.StatusBadRequest)
		return
	}

	reportWeight := calculateReportWeight(user, time.Now().UTC())
	silencedNow := false
	alreadyReported := false
	dominantReason := reason

	err = database.DB.Transaction(func(tx *gorm.DB) error {
		report := models.ReelReport{
			ReelID:  reelID,
			UserID:  user.ID,
			Reason:  reason,
			Details: details,
			Weight:  reportWeight,
		}
		res := tx.Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "reel_id"}, {Name: "user_id"}},
			DoNothing: true,
		}).Create(&report)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			alreadyReported = true
			return nil
		}

		if err := tx.Model(&models.Reel{}).Where("id = ?", reelID).Updates(map[string]interface{}{
			"reports_count":          gorm.Expr("reports_count + 1"),
			"weighted_reports_score": gorm.Expr("COALESCE(weighted_reports_score, 0) + ?", reportWeight),
		}).Error; err != nil {
			return err
		}

		var updated models.Reel
		if err := tx.Select("id, reports_count, weighted_reports_score, views_count, active, moderation_status").First(&updated, "id = ?", reelID).Error; err != nil {
			return err
		}

		// Determinar el motivo dominante ponderado para enrutar correctamente la IA bajo demanda
		type reasonAgg struct {
			Reason string
			Total  float64
		}
		var topReason reasonAgg
		if err := tx.Model(&models.ReelReport{}).
			Select("reason, COALESCE(SUM(weight), 0) as total").
			Where("reel_id = ?", reelID).
			Group("reason").
			Order("total DESC").
			Limit(1).
			Scan(&topReason).Error; err == nil && topReason.Reason != "" {
			dominantReason = topReason.Reason
		}

		if updated.Active && shouldQuarantineReel(updated.WeightedReportsScore, updated.ViewsCount, updated.ModerationStatus, dominantReason) {
			if err := tx.Model(&models.Reel{}).Where("id = ?", reelID).Updates(map[string]interface{}{
				"active":              false,
				"silenced_by_reports": true,
				"moderation_status":   ModerationStatusQuarantined,
			}).Error; err != nil {
				return err
			}
			silencedNow = true
		}

		return nil
	})

	if err != nil {
		http.Error(w, `{"error":"Error al registrar el reporte"}`, http.StatusInternalServerError)
		return
	}

	if alreadyReported {
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "already_reported",
			"message": "Ya habías reportado este video anteriormente",
		})
		return
	}

	// Si acaba de entrar en cuarentena, disparar análisis de IA bajo demanda según el motivo dominante
	if silencedNow {
		invalidateReelsFeedCache()
		invalidateReelMeta(reelID)
		RunQuarantineAIReview(reelID, dominantReason)
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":   "reported",
		"silenced": silencedNow,
		"message":  "Gracias por reportar. Revisaremos este video.",
	})
}

// AdminListReportedReels lista videos reportados o silenciados para el panel de control del administrador
func AdminListReportedReels(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !isReelAdmin(user) || !ok {
		http.Error(w, `{"error":"Acceso restringido al administrador"}`, http.StatusForbidden)
		return
	}

	var reels []models.Reel
	if err := database.DB.Preload("Creator").
		Where("reports_count > 0 OR silenced_by_reports = ? OR moderation_status IN ?", true, []string{ModerationStatusQuarantined, ModerationStatusPendingScan}).
		Order("silenced_by_reports DESC, weighted_reports_score DESC, reports_count DESC, updated_at DESC").
		Limit(100).
		Find(&reels).Error; err != nil {
		http.Error(w, `{"error":"Error consultando videos reportados"}`, http.StatusInternalServerError)
		return
	}

	for i := range reels {
		resolveReelMediaURLs(&reels[i])
		reels[i].CreatorUsername = reels[i].Creator.Username
		reels[i].CreatorAvatar = reels[i].Creator.ProfilePic
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"reels": reels,
		"count": len(reels),
	})
}

type AdminModerateReelRequest struct {
	Action string `json:"action"` // "restore", "silence", "delete"
}

// AdminModerateReel permite al administrador restaurar, silenciar o eliminar un reel reportado
func AdminModerateReel(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !isReelAdmin(user) || !ok {
		http.Error(w, `{"error":"Acceso restringido al administrador"}`, http.StatusForbidden)
		return
	}

	reelID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"ID de reel inválido"}`, http.StatusBadRequest)
		return
	}

	var req AdminModerateReelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Cuerpo de petición inválido"}`, http.StatusBadRequest)
		return
	}

	switch strings.ToLower(strings.TrimSpace(req.Action)) {
	case "restore":
		// Anti-brigading: penalizar Trust Score de quienes reportaron en falso un video aprobado por el admin
		var reporterIDs []uuid.UUID
		_ = database.DB.Model(&models.ReelReport{}).Where("reel_id = ?", reelID).Pluck("user_id", &reporterIDs).Error
		if len(reporterIDs) > 0 {
			_ = database.DB.Model(&models.User{}).
				Where("id IN ?", reporterIDs).
				Update("report_trust_score", gorm.Expr("GREATEST(0.10, COALESCE(report_trust_score, 1.0) - 0.20)")).Error
		}
		if err := database.DB.Model(&models.Reel{}).Where("id = ?", reelID).Updates(map[string]interface{}{
			"active":                 true,
			"silenced_by_reports":    false,
			"reports_count":          0,
			"weighted_reports_score": 0,
			"moderation_status":      ModerationStatusVerifiedSafe,
			"moderation_reason":      "Aprobado manualmente por administrador",
		}).Error; err != nil {
			http.Error(w, `{"error":"Error al restaurar el video"}`, http.StatusInternalServerError)
			return
		}
		_ = database.DB.Where("reel_id = ?", reelID).Delete(&models.ReelReport{}).Error
	case "silence":
		if err := database.DB.Model(&models.Reel{}).Where("id = ?", reelID).Updates(map[string]interface{}{
			"active":              false,
			"silenced_by_reports": true,
			"moderation_status":   ModerationStatusQuarantined,
		}).Error; err != nil {
			http.Error(w, `{"error":"Error al silenciar el video"}`, http.StatusInternalServerError)
			return
		}
	case "delete", "strike_delete", "ban_nsfw":
		actionLower := strings.ToLower(strings.TrimSpace(req.Action))
		var reelToDelete models.Reel
		_ = database.DB.First(&reelToDelete, "id = ?", reelID).Error
		if err := database.DB.Where("id = ?", reelID).Delete(&models.Reel{}).Error; err != nil {
			http.Error(w, `{"error":"Error al eliminar el video"}`, http.StatusInternalServerError)
			return
		}
		if reelToDelete.ID != uuid.Nil {
			if actionLower == "ban_nsfw" {
				if strings.TrimSpace(reelToDelete.ContentHash) != "" {
					storeBannedFrameHashes(reelToDelete.ID, []string{reelToDelete.ContentHash}, "admin_nsfw_gore")
				}
				banUserAndDeviceImmediately(reelToDelete.CreatorID, "admin_ban_nsfw")
			} else if actionLower == "strike_delete" {
				applyModerationStrike(reelToDelete.CreatorID, "admin_strike_delete")
			}
			cleanupReelStorageFiles(&reelToDelete)
		}
	default:
		http.Error(w, `{"error":"Acción inválida (usa restore, silence, delete, strike_delete o ban_nsfw)"}`, http.StatusBadRequest)
		return
	}

	invalidateReelsFeedCache()
	invalidateReelMeta(reelID)

	_ = json.NewEncoder(w).Encode(map[string]string{
		"status": "ok",
		"action": req.Action,
	})
}

// GetReelComments obtiene los comentarios de un reel
func GetReelComments(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	reelID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"ID de reel inválido"}`, http.StatusBadRequest)
		return
	}

	var comments []models.ReelComment
	commentsQuery := database.DB.Where("reel_id = ?", reelID)
	if blockedIDs := getBlockedUserIDsForViewer(getOptionalUser(r)); len(blockedIDs) > 0 {
		commentsQuery = commentsQuery.Where("user_id NOT IN ?", blockedIDs)
	}
	if err := commentsQuery.
		Preload("User").
		Order("created_at ASC").
		Limit(100).
		Find(&comments).Error; err != nil {
		http.Error(w, `{"error":"Error al consultar comentarios"}`, http.StatusInternalServerError)
		return
	}

	for i := range comments {
		comments[i].Username = comments[i].User.Username
		comments[i].ProfilePic = comments[i].User.ProfilePic
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"comments": comments,
		"count":    len(comments),
	})
}

// CreateCommentRequest estructura de creación de comentario
type CreateCommentRequest struct {
	Content string `json:"content"`
}

// CreateReelComment añade un comentario a un reel
func CreateReelComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	reelID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"ID de reel inválido"}`, http.StatusBadRequest)
		return
	}

	var req CreateCommentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Cuerpo de petición inválido"}`, http.StatusBadRequest)
		return
	}

	req.Content = strings.TrimSpace(req.Content)
	if req.Content == "" || len(req.Content) > 400 {
		http.Error(w, `{"error":"El comentario no puede estar vacío ni superar 400 caracteres"}`, http.StatusBadRequest)
		return
	}

	comment := models.ReelComment{
		ReelID:  reelID,
		UserID:  user.ID,
		Content: req.Content,
	}

	err = database.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&comment).Error; err != nil {
			return err
		}
		return tx.Model(&models.Reel{}).Where("id = ?", reelID).
			Update("comments_count", gorm.Expr("comments_count + 1")).Error
	})

	if err != nil {
		http.Error(w, `{"error":"Error al guardar el comentario"}`, http.StatusInternalServerError)
		return
	}

	comment.Username = user.Username
	comment.ProfilePic = user.ProfilePic

	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(comment)
}

// DeleteReelComment borra un comentario del propio usuario
func DeleteReelComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	commentID, err := uuid.Parse(chi.URLParam(r, "comment_id"))
	if err != nil {
		http.Error(w, `{"error":"ID de comentario inválido"}`, http.StatusBadRequest)
		return
	}

	var comment models.ReelComment
	if err := database.DB.First(&comment, "id = ?", commentID).Error; err != nil {
		http.Error(w, `{"error":"Comentario no encontrado"}`, http.StatusNotFound)
		return
	}

	if comment.UserID != user.ID {
		http.Error(w, `{"error":"No puedes eliminar comentarios de otros usuarios"}`, http.StatusForbidden)
		return
	}

	err = database.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Delete(&comment).Error; err != nil {
			return err
		}
		return tx.Model(&models.Reel{}).Where("id = ?", comment.ReelID).
			Update("comments_count", gorm.Expr("GREATEST(0, comments_count - 1)")).Error
	})

	if err != nil {
		http.Error(w, `{"error":"Error al eliminar el comentario"}`, http.StatusInternalServerError)
		return
	}

	_ = json.NewEncoder(w).Encode(map[string]string{"status": "deleted"})
}

// ==============================================================================
// PERFIL DE REELS DEL USUARIO (SUBIDOS, GUARDADOS, LIKES Y MÉTRICAS)
// ==============================================================================

// computeCreatorWallet calcula saldo histórico, retiros pendientes, pagados y disponible para un creador.
func computeCreatorWallet(tx *gorm.DB, userID uuid.UUID, lifetimeViews int64, currentReelVerifiedViews int64) (effectiveViews int64, totalEarned, pendingUSD, paidUSD, availableUSD float64) {
	effectiveViews = lifetimeViews
	if currentReelVerifiedViews > effectiveViews {
		effectiveViews = currentReelVerifiedViews
	}
	totalEarned = math.Round(float64(effectiveViews)*CreatorPayoutPerViewUSD*10000) / 10000

	type payoutSum struct {
		Status string
		Total  float64
	}
	var sums []payoutSum
	tx.Model(&models.CreatorPayoutRequest{}).
		Select("status, COALESCE(SUM(amount_usd), 0) as total").
		Where("user_id = ? AND status IN ?", userID, []string{"pending", "approved", "paid"}).
		Group("status").
		Scan(&sums)

	for _, s := range sums {
		switch s.Status {
		case "pending", "approved":
			pendingUSD += s.Total
		case "paid":
			paidUSD += s.Total
		}
	}
	pendingUSD = math.Round(pendingUSD*10000) / 10000
	paidUSD = math.Round(paidUSD*10000) / 10000
	availableUSD = math.Round((totalEarned-pendingUSD-paidUSD)*10000) / 10000
	if availableUSD < 0 {
		availableUSD = 0
	}
	return
}

// GetMyUploadedReels entrega los videos subidos por el usuario autenticado con estadísticas agregadas en SQL y billetera de creador
func GetMyUploadedReels(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	type aggStats struct {
		TotalReels         int64
		TotalViews         int64
		TotalVerifiedViews int64
		TotalLikes         int64
		TotalComments      int64
		TotalSaves         int64
	}
	var agg aggStats
	database.DB.Model(&models.Reel{}).
		Select(`COUNT(*) as total_reels,
			COALESCE(SUM(views_count), 0) as total_views,
			COALESCE(SUM(verified_views_count), 0) as total_verified_views,
			COALESCE(SUM(likes_count), 0) as total_likes,
			COALESCE(SUM(comments_count), 0) as total_comments,
			COALESCE(SUM(saves_count), 0) as total_saves`).
		Where("creator_id = ?", user.ID).
		Scan(&agg)

	var reels []models.Reel
	if err := database.DB.Where("creator_id = ?", user.ID).
		Order("created_at DESC").
		Limit(120).
		Find(&reels).Error; err != nil {
		http.Error(w, `{"error":"Error al consultar videos subidos"}`, http.StatusInternalServerError)
		return
	}

	for i := range reels {
		resolveReelMediaURLs(&reels[i])
		reels[i].CreatorUsername = user.Username
		reels[i].CreatorAvatar = user.ProfilePic
		if reels[i].Orientation == "" {
			reels[i].Orientation = detectVideoOrientation(reels[i].Width, reels[i].Height, "")
		}
	}

	var followersCount, followingCount int64
	database.DB.Model(&models.UserFollow{}).Where("following_id = ?", user.ID).Count(&followersCount)
	database.DB.Model(&models.UserFollow{}).Where("follower_id = ?", user.ID).Count(&followingCount)

	effectiveVerified, totalEarned, pendingUSD, paidUSD, availableUSD := computeCreatorWallet(
		database.DB, user.ID, user.LifetimeVerifiedViews, agg.TotalVerifiedViews,
	)

	stats := models.UserReelsProfileStats{
		TotalReels:            agg.TotalReels,
		TotalViews:            agg.TotalViews,
		TotalVerifiedViews:    agg.TotalVerifiedViews,
		LifetimeVerifiedViews: effectiveVerified,
		TotalLikes:            agg.TotalLikes,
		TotalComments:         agg.TotalComments,
		TotalSaves:            agg.TotalSaves,
		FollowersCount:        followersCount,
		FollowingCount:        followingCount,
		EstimatedEarningsUSD:  totalEarned,
		PendingPayoutUSD:      pendingUSD,
		PaidOutUSD:            paidUSD,
		AvailableBalanceUSD:   availableUSD,
		MinPayoutUSD:          MinCreatorPayoutUSD,
		CanWithdraw:           availableUSD >= MinCreatorPayoutUSD,
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"user": map[string]interface{}{
			"id":            user.ID,
			"username":      user.Username,
			"profile_pic":   user.ProfilePic,
			"bio":           user.Bio,
			"twitch_url":    user.TwitchURL,
			"tiktok_url":    user.TikTokURL,
			"youtube_url":   user.YouTubeURL,
			"instagram_url": user.InstagramURL,
			"kick_url":      user.KickURL,
		},
		"stats": stats,
		"reels": reels,
	})
}

// GetMyLikedReels entrega los videos que le gustan al usuario autenticado
func GetMyLikedReels(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	var reels []models.Reel
	err := database.DB.Table("reels").
		Joins("INNER JOIN reel_likes ON reel_likes.reel_id = reels.id").
		Where("reel_likes.user_id = ? AND reels.active = ? AND reels.deleted_at IS NULL", user.ID, true).
		Order("reel_likes.created_at DESC").
		Preload("Creator").
		Find(&reels).Error

	if err != nil {
		http.Error(w, `{"error":"Error al consultar videos con me gusta"}`, http.StatusInternalServerError)
		return
	}

	for i := range reels {
		resolveReelMediaURLs(&reels[i])
		reels[i].HasLiked = true
		reels[i].CreatorUsername = reels[i].Creator.Username
		reels[i].CreatorAvatar = reels[i].Creator.ProfilePic
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"reels": reels,
		"count": len(reels),
	})
}

// GetMySavedReels entrega los videos guardados en favoritos por el usuario autenticado
func GetMySavedReels(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	var reels []models.Reel
	err := database.DB.Table("reels").
		Joins("INNER JOIN reel_saves ON reel_saves.reel_id = reels.id").
		Where("reel_saves.user_id = ? AND reels.active = ? AND reels.deleted_at IS NULL", user.ID, true).
		Order("reel_saves.created_at DESC").
		Preload("Creator").
		Find(&reels).Error

	if err != nil {
		http.Error(w, `{"error":"Error al consultar videos guardados"}`, http.StatusInternalServerError)
		return
	}

	for i := range reels {
		resolveReelMediaURLs(&reels[i])
		reels[i].HasSaved = true
		reels[i].CreatorUsername = reels[i].Creator.Username
		reels[i].CreatorAvatar = reels[i].Creator.ProfilePic
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"reels": reels,
		"count": len(reels),
	})
}

// GetUserReelsProfile obtiene el perfil público de reels de cualquier invocador (incluye bio, redes, vistas y seguidores)
func GetUserReelsProfile(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	targetUserID, err := uuid.Parse(chi.URLParam(r, "user_id"))
	if err != nil {
		http.Error(w, `{"error":"ID de usuario inválido"}`, http.StatusBadRequest)
		return
	}

	var targetUser models.User
	if err := database.DB.Select("id, username, profile_pic, bio, twitch_url, tiktok_url, youtube_url, instagram_url, kick_url, created_at").First(&targetUser, "id = ?", targetUserID).Error; err != nil {
		http.Error(w, `{"error":"Usuario no encontrado"}`, http.StatusNotFound)
		return
	}

	type aggStats struct {
		TotalReels         int64
		TotalViews         int64
		TotalVerifiedViews int64
		TotalLikes         int64
	}
	var agg aggStats
	database.DB.Model(&models.Reel{}).
		Select(`COUNT(*) as total_reels,
			COALESCE(SUM(views_count), 0) as total_views,
			COALESCE(SUM(verified_views_count), 0) as total_verified_views,
			COALESCE(SUM(likes_count), 0) as total_likes`).
		Where("creator_id = ? AND active = ?", targetUserID, true).
		Scan(&agg)

	var reels []models.Reel
	if err := database.DB.Where("creator_id = ? AND active = ?", targetUserID, true).
		Order("created_at DESC").
		Limit(120).
		Find(&reels).Error; err != nil {
		http.Error(w, `{"error":"Error al consultar reels del usuario"}`, http.StatusInternalServerError)
		return
	}

	var followersCount, followingCount int64
	database.DB.Model(&models.UserFollow{}).Where("following_id = ?", targetUserID).Count(&followersCount)
	database.DB.Model(&models.UserFollow{}).Where("follower_id = ?", targetUserID).Count(&followingCount)

	isFollowing := false
	if currentUser := getOptionalUser(r); currentUser != nil && currentUser.ID != targetUserID {
		var cnt int64
		database.DB.Model(&models.UserFollow{}).
			Where("follower_id = ? AND following_id = ?", currentUser.ID, targetUserID).
			Count(&cnt)
		isFollowing = cnt > 0
	}

	for i := range reels {
		resolveReelMediaURLs(&reels[i])
		reels[i].CreatorUsername = targetUser.Username
		reels[i].CreatorAvatar = targetUser.ProfilePic
		reels[i].CreatorFollowersCount = followersCount
		reels[i].IsFollowing = isFollowing
		if reels[i].Orientation == "" {
			reels[i].Orientation = detectVideoOrientation(reels[i].Width, reels[i].Height, "")
		}
	}

	stats := models.UserReelsProfileStats{
		TotalReels:         agg.TotalReels,
		TotalViews:         agg.TotalViews,
		TotalVerifiedViews: agg.TotalVerifiedViews,
		TotalLikes:         agg.TotalLikes,
		FollowersCount:     followersCount,
		FollowingCount:     followingCount,
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"user": map[string]interface{}{
			"id":            targetUser.ID,
			"username":      targetUser.Username,
			"profile_pic":   targetUser.ProfilePic,
			"bio":           targetUser.Bio,
			"twitch_url":    targetUser.TwitchURL,
			"tiktok_url":    targetUser.TikTokURL,
			"youtube_url":   targetUser.YouTubeURL,
			"instagram_url": targetUser.InstagramURL,
			"kick_url":      targetUser.KickURL,
			"is_following":  isFollowing,
		},
		"stats": stats,
		"reels": reels,
	})
}

// ToggleFollowCreator sigue o deja de seguir a un creador en PostgreSQL
func ToggleFollowCreator(w http.ResponseWriter, r *http.Request) {
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
		http.Error(w, `{"error":"No puedes seguirte a ti mismo"}`, http.StatusBadRequest)
		return
	}

	var exists int64
	database.DB.Model(&models.User{}).Where("id = ?", targetUserID).Count(&exists)
	if exists == 0 {
		http.Error(w, `{"error":"Usuario no encontrado"}`, http.StatusNotFound)
		return
	}

	var following bool
	var followersCount int64

	err = database.DB.Transaction(func(tx *gorm.DB) error {
		var existing models.UserFollow
		errFind := tx.Where("follower_id = ? AND following_id = ?", user.ID, targetUserID).First(&existing).Error
		if errFind == nil {
			if errDel := tx.Delete(&existing).Error; errDel != nil {
				return errDel
			}
			following = false
		} else {
			entry := models.UserFollow{FollowerID: user.ID, FollowingID: targetUserID}
			if errIns := tx.Create(&entry).Error; errIns != nil {
				return errIns
			}
			following = true
		}
		return tx.Model(&models.UserFollow{}).Where("following_id = ?", targetUserID).Count(&followersCount).Error
	})

	if err != nil {
		http.Error(w, `{"error":"Error al actualizar seguimiento"}`, http.StatusInternalServerError)
		return
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"following":       following,
		"followers_count": followersCount,
	})
}

// ==============================================================================
// SISTEMA DE RETIROS DE CREADORES ($0.01 / 1,000 VISTAS VERIFICADAS • MÍN. $100)
// ==============================================================================

type RequestCreatorPayoutBody struct {
	PayoutMethod      string `json:"payout_method"`      // "paypal", "wise", "binance", "bank"
	PayoutDestination string `json:"payout_destination"` // Correo de PayPal, ID Binance, IBAN/cuenta
}

// RequestCreatorPayout crea una solicitud de retiro si el creador tiene >= $100 USD disponibles
func RequestCreatorPayout(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	var req RequestCreatorPayoutBody
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Cuerpo de petición inválido"}`, http.StatusBadRequest)
		return
	}

	method := strings.ToLower(strings.TrimSpace(req.PayoutMethod))
	switch method {
	case "paypal", "wise", "binance", "bank":
	default:
		http.Error(w, `{"error":"Método de pago inválido (usa paypal, wise, binance o bank)"}`, http.StatusBadRequest)
		return
	}

	dest := strings.TrimSpace(req.PayoutDestination)
	if len(dest) < 4 || len(dest) > 255 {
		http.Error(w, `{"error":"Debes ingresar una cuenta o correo válido para recibir el pago"}`, http.StatusBadRequest)
		return
	}

	var created models.CreatorPayoutRequest
	var availableBefore float64

	err := database.DB.Transaction(func(tx *gorm.DB) error {
		var lockedUser models.User
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&lockedUser, "id = ?", user.ID).Error; err != nil {
			return err
		}

		var currentReelVerified int64
		tx.Model(&models.Reel{}).
			Select("COALESCE(SUM(verified_views_count), 0)").
			Where("creator_id = ?", user.ID).
			Scan(&currentReelVerified)

		effectiveViews, _, _, _, avail := computeCreatorWallet(tx, user.ID, lockedUser.LifetimeVerifiedViews, currentReelVerified)
		availableBefore = avail
		if avail < MinCreatorPayoutUSD {
			return fmt.Errorf("INSUFFICIENT_BALANCE")
		}

		created = models.CreatorPayoutRequest{
			UserID:                user.ID,
			AmountUSD:             avail,
			VerifiedViewsSnapshot: effectiveViews,
			PayoutMethod:          method,
			PayoutDestination:     dest,
			Status:                "pending",
		}
		return tx.Create(&created).Error
	})

	if err != nil {
		if err.Error() == "INSUFFICIENT_BALANCE" {
			http.Error(w, fmt.Sprintf(`{"error":"El mínimo de retiro es $%.2f USD. Tu saldo disponible actual es $%.2f USD."}`, MinCreatorPayoutUSD, availableBefore), http.StatusBadRequest)
			return
		}
		http.Error(w, `{"error":"Error al registrar la solicitud de retiro"}`, http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "pending",
		"payout":  created,
		"message": "Solicitud de retiro enviada. Será revisada y procesada por el equipo.",
	})
}

// GetMyPayoutRequests devuelve el historial de retiros y estado actual de billetera del creador
func GetMyPayoutRequests(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	var currentReelVerified int64
	database.DB.Model(&models.Reel{}).
		Select("COALESCE(SUM(verified_views_count), 0)").
		Where("creator_id = ?", user.ID).
		Scan(&currentReelVerified)

	effectiveViews, totalEarned, pendingUSD, paidUSD, availableUSD := computeCreatorWallet(
		database.DB, user.ID, user.LifetimeVerifiedViews, currentReelVerified,
	)

	var payouts []models.CreatorPayoutRequest
	database.DB.Where("user_id = ?", user.ID).Order("created_at DESC").Limit(50).Find(&payouts)

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"wallet": map[string]interface{}{
			"lifetime_verified_views": effectiveViews,
			"rate_per_1000_views_usd": CreatorPayoutPerViewUSD * 1000.0,
			"total_earned_usd":        totalEarned,
			"pending_payout_usd":      pendingUSD,
			"paid_out_usd":            paidUSD,
			"available_balance_usd":   availableUSD,
			"min_payout_usd":          MinCreatorPayoutUSD,
			"can_withdraw":            availableUSD >= MinCreatorPayoutUSD,
		},
		"payouts": payouts,
	})
}

// AdminListPayoutRequests lista solicitudes de retiro para revisión del administrador
func AdminListPayoutRequests(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !isReelAdmin(user) || !ok {
		http.Error(w, `{"error":"Acceso restringido al administrador"}`, http.StatusForbidden)
		return
	}

	var payouts []models.CreatorPayoutRequest
	if err := database.DB.Preload("User").
		Order("CASE status WHEN 'pending' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END, created_at DESC").
		Limit(100).
		Find(&payouts).Error; err != nil {
		http.Error(w, `{"error":"Error consultando solicitudes de retiro"}`, http.StatusInternalServerError)
		return
	}

	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"payouts": payouts,
		"count":   len(payouts),
	})
}

type AdminReviewPayoutBody struct {
	Status     string `json:"status"` // "approved", "paid", "rejected"
	AdminNotes string `json:"admin_notes"`
}

// AdminReviewPayoutRequest permite al administrador aprobar, marcar como pagado o rechazar un retiro
func AdminReviewPayoutRequest(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !isReelAdmin(user) || !ok {
		http.Error(w, `{"error":"Acceso restringido al administrador"}`, http.StatusForbidden)
		return
	}

	payoutID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"ID de retiro inválido"}`, http.StatusBadRequest)
		return
	}

	var req AdminReviewPayoutBody
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Cuerpo de petición inválido"}`, http.StatusBadRequest)
		return
	}

	status := strings.ToLower(strings.TrimSpace(req.Status))
	switch status {
	case "approved", "paid", "rejected":
	default:
		http.Error(w, `{"error":"Estado inválido (usa approved, paid o rejected)"}`, http.StatusBadRequest)
		return
	}

	notes := strings.TrimSpace(req.AdminNotes)
	if len(notes) > 300 {
		notes = notes[:300]
	}

	if err := database.DB.Model(&models.CreatorPayoutRequest{}).Where("id = ?", payoutID).Updates(map[string]interface{}{
		"status":      status,
		"admin_notes": notes,
	}).Error; err != nil {
		http.Error(w, `{"error":"Error al actualizar la solicitud de retiro"}`, http.StatusInternalServerError)
		return
	}

	_ = json.NewEncoder(w).Encode(map[string]string{
		"status": status,
	})
}

// DeleteMyReel elimina un reel subido por el propio creador y limpia sus archivos en R2/S3
func DeleteMyReel(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, `{"error":"No autorizado"}`, http.StatusUnauthorized)
		return
	}

	reelID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, `{"error":"ID de reel inválido"}`, http.StatusBadRequest)
		return
	}

	var reel models.Reel
	if err := database.DB.First(&reel, "id = ?", reelID).Error; err != nil {
		http.Error(w, `{"error":"Reel no encontrado"}`, http.StatusNotFound)
		return
	}

	if reel.CreatorID != user.ID && !isReelAdmin(user) {
		http.Error(w, `{"error":"Solo puedes eliminar tus propios reels"}`, http.StatusForbidden)
		return
	}

	if err := database.DB.Delete(&reel).Error; err != nil {
		http.Error(w, `{"error":"Error al eliminar reel"}`, http.StatusInternalServerError)
		return
	}

	invalidateReelsFeedCache()
	invalidateReelMeta(reel.ID)
	cleanupReelStorageFiles(&reel)

	_ = json.NewEncoder(w).Encode(map[string]string{"status": "deleted"})
}
