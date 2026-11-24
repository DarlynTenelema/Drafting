package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/middleware"
	"backend/internal/models"
	"backend/internal/tts"
	"backend/internal/utils"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type DraftRequest struct {
	ImageBase64      string `json:"image_base64,omitempty"`
	DraftContext     string `json:"draft_context,omitempty"`
	MainRole         string `json:"main_role,omitempty"`
	SecondaryRole    string `json:"secondary_role,omitempty"`
	AutofillRole     string `json:"autofill_role,omitempty"`
	OtpChampions     string `json:"otp_champions,omitempty"`
	Language         string `json:"language,omitempty"`
	GameMode         string `json:"game_mode,omitempty"` // "wild_rift" o "lol_pc"
	ModelTier        string `json:"model_tier,omitempty"` // "classic", "flake", "aureon"
	ExcludeChampions string `json:"exclude_champions,omitempty"`
}

type ManualDraftRequest struct {
	MainRole         string `json:"main_role"`
	MyChampion       string `json:"my_champion,omitempty"`
	EnemyChampion    string `json:"enemy_champion"`
	Language         string `json:"language,omitempty"`
	GameMode         string `json:"game_mode,omitempty"` // "wild_rift" o "lol_pc"
	ModelTier        string `json:"model_tier,omitempty"`
	ExcludeChampions string `json:"exclude_champions,omitempty"`
}

type ChatDraftRequest struct {
	Message      string `json:"message"`
	DraftContext string `json:"draft_context,omitempty"`
	OtpChampions string `json:"otp_champions,omitempty"`
	Language     string `json:"language,omitempty"`
	GameMode     string `json:"game_mode,omitempty"`
	ModelTier    string `json:"model_tier,omitempty"`
}

type DraftResponse struct {
	Recommendation   string `json:"recommendation"`
	VoiceScript      string `json:"voice_script,omitempty"`
	AudioBase64      string `json:"audio_base64,omitempty"`
	ModelTier        string `json:"model_tier"`
	DraftContext     string `json:"draft_context,omitempty"`
	AvailableQueries int    `json:"available_queries"`
	ClassicQueries   int    `json:"classic_queries"`
	FlakeQueries     int    `json:"flake_queries"`
	AureonQueries    int    `json:"aureon_queries"`
	BlockedByGuard   bool   `json:"blocked_by_guard,omitempty"`
}

func noQueriesMessage(lang string, tier string) string {
	modelLabel := "Classic"
	switch models.NormalizeModelTier(tier) {
	case models.ModelFlake:
		modelLabel = "Flake 1.0"
	case models.ModelAureon:
		modelLabel = "Aureon 1.0"
	}
	switch gemini.NormalizeLanguage(lang) {
	case "pt":
		return fmt.Sprintf("Sem consultas de %s disponíveis. Abra o Drafting para recarregar.", modelLabel)
	case "en":
		return fmt.Sprintf("No %s queries available. Open Drafting to recharge.", modelLabel)
	case "fr":
		return fmt.Sprintf("Aucune requête %s disponible. Ouvre Drafting pour recharger.", modelLabel)
	default:
		return fmt.Sprintf("Sin consultas de %s disponibles. Abre Drafting para recargar.", modelLabel)
	}
}

func chatNotAllowedClassicMessage(lang string) string {
	switch gemini.NormalizeLanguage(lang) {
	case "pt":
		return "O chat tático está disponível apenas nos modelos Flake 1.0 e Aureon 1.0."
	case "en":
		return "Tactical chat is only available on Flake 1.0 and Aureon 1.0 models."
	case "fr":
		return "Le chat tactique est disponible uniquement sur les modèles Flake 1.0 et Aureon 1.0."
	default:
		return "El chat táctico solo está disponible en los modelos Flake 1.0 y Aureon 1.0."
	}
}

// reserveUserQueryForModel reserva y descuenta atómicamente 1 consulta con bloqueo FOR UPDATE
// ANTES de invocar Vertex AI, evitando condiciones de carrera (race conditions).
func reserveUserQueryForModel(user *models.User, tier string) (models.ConsumeModelQuerySource, bool, error) {
	now := time.Now().UTC()
	today := now.Format("2006-01-02")
	var src models.ConsumeModelQuerySource
	var reserved bool

	err := database.DB.Transaction(func(tx *gorm.DB) error {
		var locked models.User
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", user.ID).First(&locked).Error; err != nil {
			return err
		}

		locked.RefreshClassicDaily(now)
		locked.ResetModelAdLimitsIfNewDay(today)
		locked.SyncModelWalletsToTotals()

		var ok bool
		src, ok = locked.ConsumeModelQueryWithSource(tier, now)
		if !ok {
			*user = locked
			return nil
		}

		locked.LastDraftAt = now
		if err := tx.Model(&locked).Updates(map[string]interface{}{
			"classic_daily":            locked.ClassicDaily,
			"classic_ad":               locked.ClassicAd,
			"classic_purchased":        locked.ClassicPurchased,
			"classic_last_recharge_at": locked.ClassicLastRechargeAt,
			"flake_ad":                 locked.FlakeAd,
			"flake_purchased":          locked.FlakePurchased,
			"flake_ads_today":          locked.FlakeAdsToday,
			"flake_last_ad_date":       locked.FlakeLastAdDate,
			"aureon_ad":                locked.AureonAd,
			"aureon_purchased":         locked.AureonPurchased,
			"aureon_ads_today":         locked.AureonAdsToday,
			"aureon_last_ad_date":      locked.AureonLastAdDate,
			"daily_queries":            locked.DailyQueries,
			"ad_queries":               locked.AdQueries,
			"purchased_queries":        locked.PurchasedQueries,
			"available_queries":        locked.AvailableQueries,
			"last_daily_reward_date":   locked.LastDailyRewardDate,
			"last_draft_at":            locked.LastDraftAt,
		}).Error; err != nil {
			return err
		}

		*user = locked
		reserved = true
		return nil
	})

	return src, reserved, err
}

// refundUserQueryForModel devuelve atómicamente la consulta reservada si la llamada a Vertex AI falla.
func refundUserQueryForModel(user *models.User, src models.ConsumeModelQuerySource) {
	if src == models.QuerySourceNone || user == nil {
		return
	}
	_ = database.DB.Transaction(func(tx *gorm.DB) error {
		var locked models.User
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("id = ?", user.ID).First(&locked).Error; err != nil {
			return err
		}
		locked.RefundModelQuery(src)
		if err := tx.Model(&locked).Updates(map[string]interface{}{
			"classic_daily":     locked.ClassicDaily,
			"classic_ad":        locked.ClassicAd,
			"classic_purchased": locked.ClassicPurchased,
			"flake_ad":          locked.FlakeAd,
			"flake_purchased":   locked.FlakePurchased,
			"aureon_ad":         locked.AureonAd,
			"aureon_purchased":  locked.AureonPurchased,
			"daily_queries":     locked.DailyQueries,
			"ad_queries":        locked.AdQueries,
			"purchased_queries": locked.PurchasedQueries,
			"available_queries": locked.AvailableQueries,
		}).Error; err != nil {
			return err
		}
		*user = locked
		return nil
	})
}

func recordDraftApiUsage(user *models.User, tokens int32) {
	database.DB.Create(&models.ApiUsage{UserID: user.ID, TokensUsed: int(tokens), CreatedAt: time.Now().UTC()})
}

func AnalyzeDraft(w http.ResponseWriter, r *http.Request) {
	var req DraftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(req.ImageBase64) == "" && strings.TrimSpace(req.DraftContext) == "" {
		http.Error(w, "image_base64 or draft_context is required", http.StatusBadRequest)
		return
	}

	lang := strings.TrimSpace(req.Language)
	if lang == "" {
		lang = strings.TrimSpace(r.Header.Get("Accept-Language"))
	}
	lang = gemini.NormalizeLanguage(lang)

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	modelTier := models.NormalizeModelTier(req.ModelTier)
	reservedSource, reserved, err := reserveUserQueryForModel(user, modelTier)
	if err != nil {
		http.Error(w, "Error verificando saldo de consultas", http.StatusInternalServerError)
		return
	}
	if !reserved {
		http.Error(w, noQueriesMessage(lang, modelTier), http.StatusPaymentRequired)
		return
	}

	gameMode := strings.TrimSpace(strings.ToLower(req.GameMode))
	if gameMode == "" {
		gameMode = "wild_rift"
	}

	var (
		recommendation string
		voiceScript    string
		audioBase64    string
		draftContext   string
		tokens         int32
	)

	// Si ya existe draft_context y NO se envía imagen nueva, ejecutar reconsulta ligera sin imagen
	if strings.TrimSpace(req.ImageBase64) == "" && strings.TrimSpace(req.DraftContext) != "" {
		recommendation, draftContext, tokens, err = gemini.ReconsultDraftFromContext(
			r.Context(),
			req.DraftContext,
			req.OtpChampions,
			gameMode,
			lang,
			strings.TrimSpace(req.ExcludeChampions),
		)
	} else {
		aiRes, aiErr := gemini.AnalyzeDraftByModel(
			r.Context(),
			modelTier,
			req.ImageBase64,
			req.MainRole,
			req.SecondaryRole,
			req.AutofillRole,
			gameMode,
			req.OtpChampions,
			lang,
			strings.TrimSpace(req.ExcludeChampions),
		)
		err = aiErr
		recommendation = aiRes.ScreenText
		voiceScript = aiRes.VoiceScript
		draftContext = aiRes.DraftContext
		tokens = aiRes.Tokens
	}

	if err != nil {
		refundUserQueryForModel(user, reservedSource)
		log.Printf("AnalyzeDraft Error (%s): %v", modelTier, err)
		http.Error(w, fmt.Sprintf("Error al generar recomendación: %v", err), http.StatusInternalServerError)
		return
	}

	// Para Aureon 1.0, sintetizar el guion de voz extendido con Google Cloud WaveNet
	if modelTier == models.ModelAureon && strings.TrimSpace(voiceScript) != "" {
		if audioB64, _, ttsErr := tts.SynthesizeWaveNet(r.Context(), voiceScript, lang); ttsErr == nil {
			audioBase64 = audioB64
		} else {
			log.Printf("⚠️ WaveNet fallback a TTS local en Aureon: %v", ttsErr)
		}
	}

	recordDraftApiUsage(user, tokens)

	resp := DraftResponse{
		Recommendation:   recommendation,
		VoiceScript:      voiceScript,
		AudioBase64:      audioBase64,
		ModelTier:        modelTier,
		DraftContext:     draftContext,
		AvailableQueries: user.AvailableQueries,
		ClassicQueries:   user.ClassicQueries(),
		FlakeQueries:     user.FlakeQueries(),
		AureonQueries:    user.AureonQueries(),
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// ReconsultDraft maneja las reconsultas usando únicamente el contexto guardado de la primera captura (sin imagen)
func ReconsultDraft(w http.ResponseWriter, r *http.Request) {
	var req DraftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(req.DraftContext) == "" && strings.TrimSpace(req.ImageBase64) == "" {
		http.Error(w, "draft_context is required", http.StatusBadRequest)
		return
	}

	lang := strings.TrimSpace(req.Language)
	if lang == "" {
		lang = strings.TrimSpace(r.Header.Get("Accept-Language"))
	}
	lang = gemini.NormalizeLanguage(lang)

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	modelTier := models.NormalizeModelTier(req.ModelTier)
	reservedSource, reserved, err := reserveUserQueryForModel(user, modelTier)
	if err != nil {
		http.Error(w, "Error verificando saldo de consultas", http.StatusInternalServerError)
		return
	}
	if !reserved {
		http.Error(w, noQueriesMessage(lang, modelTier), http.StatusPaymentRequired)
		return
	}

	gameMode := strings.TrimSpace(strings.ToLower(req.GameMode))
	if gameMode == "" {
		gameMode = "wild_rift"
	}

	recommendation, draftContext, tokens, err := gemini.ReconsultDraftFromContext(
		r.Context(),
		req.DraftContext,
		req.OtpChampions,
		gameMode,
		lang,
		strings.TrimSpace(req.ExcludeChampions),
	)
	if err != nil {
		refundUserQueryForModel(user, reservedSource)
		log.Printf("ReconsultDraft Error: %v", err)
		http.Error(w, fmt.Sprintf("Error al reconsultar alternativas: %v", err), http.StatusInternalServerError)
		return
	}

	var audioBase64 string
	if modelTier == models.ModelAureon && strings.TrimSpace(recommendation) != "" {
		if audioB64, _, ttsErr := tts.SynthesizeWaveNet(r.Context(), recommendation, lang); ttsErr == nil {
			audioBase64 = audioB64
		}
	}

	recordDraftApiUsage(user, tokens)

	resp := DraftResponse{
		Recommendation:   recommendation,
		AudioBase64:      audioBase64,
		ModelTier:        modelTier,
		DraftContext:     draftContext,
		AvailableQueries: user.AvailableQueries,
		ClassicQueries:   user.ClassicQueries(),
		FlakeQueries:     user.FlakeQueries(),
		AureonQueries:    user.AureonQueries(),
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// ChatDraft maneja el Chatbot en tiempo real (solo habilitado en Flake 1.0 y Aureon 1.0)
func ChatDraft(w http.ResponseWriter, r *http.Request) {
	var req ChatDraftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	lang := strings.TrimSpace(req.Language)
	if lang == "" {
		lang = strings.TrimSpace(r.Header.Get("Accept-Language"))
	}
	lang = gemini.NormalizeLanguage(lang)

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	modelTier := models.NormalizeModelTier(req.ModelTier)
	if modelTier == models.ModelClassic {
		http.Error(w, chatNotAllowedClassicMessage(lang), http.StatusForbidden)
		return
	}

	// 1. Asistente Puente: Validar groserías, siglas ofensivas (SPCRF), links y máximo 50 palabras ANTES de llegar a la IA
	if valid, guardMsg := utils.ValidateDraftChatMessage(req.Message, lang); !valid {
		resp := DraftResponse{
			Recommendation:   guardMsg,
			ModelTier:        modelTier,
			DraftContext:     req.DraftContext,
			AvailableQueries: user.AvailableQueries,
			ClassicQueries:   user.ClassicQueries(),
			FlakeQueries:     user.FlakeQueries(),
			AureonQueries:    user.AureonQueries(),
			BlockedByGuard:   true,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
		return
	}

	reservedSource, reserved, err := reserveUserQueryForModel(user, modelTier)
	if err != nil {
		http.Error(w, "Error verificando saldo de consultas", http.StatusInternalServerError)
		return
	}
	if !reserved {
		http.Error(w, noQueriesMessage(lang, modelTier), http.StatusPaymentRequired)
		return
	}

	gameMode := strings.TrimSpace(strings.ToLower(req.GameMode))
	if gameMode == "" {
		gameMode = "wild_rift"
	}

	answer, tokens, err := gemini.AnalyzeDraftChat(
		r.Context(),
		strings.TrimSpace(req.Message),
		req.DraftContext,
		req.OtpChampions,
		gameMode,
		lang,
	)
	if err != nil {
		refundUserQueryForModel(user, reservedSource)
		log.Printf("ChatDraft Error: %v", err)
		http.Error(w, fmt.Sprintf("Error en chat táctico: %v", err), http.StatusInternalServerError)
		return
	}

	var audioBase64 string
	if modelTier == models.ModelAureon && strings.TrimSpace(answer) != "" {
		if audioB64, _, ttsErr := tts.SynthesizeWaveNet(r.Context(), answer, lang); ttsErr == nil {
			audioBase64 = audioB64
		}
	}

	recordDraftApiUsage(user, tokens)

	resp := DraftResponse{
		Recommendation:   answer,
		AudioBase64:      audioBase64,
		ModelTier:        modelTier,
		DraftContext:     req.DraftContext,
		AvailableQueries: user.AvailableQueries,
		ClassicQueries:   user.ClassicQueries(),
		FlakeQueries:     user.FlakeQueries(),
		AureonQueries:    user.AureonQueries(),
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func AnalyzeManualDraft(w http.ResponseWriter, r *http.Request) {
	var req ManualDraftRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	enemyChamp := strings.TrimSpace(req.EnemyChampion)
	myChamp := strings.TrimSpace(req.MyChampion)
	mainRole := strings.TrimSpace(req.MainRole)
	if enemyChamp == "" && myChamp == "" {
		http.Error(w, "enemy_champion or my_champion is required", http.StatusBadRequest)
		return
	}
	if mainRole == "" {
		mainRole = "Mid"
	}

	lang := strings.TrimSpace(req.Language)
	if lang == "" {
		lang = strings.TrimSpace(r.Header.Get("Accept-Language"))
	}
	lang = gemini.NormalizeLanguage(lang)

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	modelTier := models.NormalizeModelTier(req.ModelTier)
	reservedSource, reserved, err := reserveUserQueryForModel(user, modelTier)
	if err != nil {
		http.Error(w, "Error verificando saldo de consultas", http.StatusInternalServerError)
		return
	}
	if !reserved {
		http.Error(w, noQueriesMessage(lang, modelTier), http.StatusPaymentRequired)
		return
	}

	gameMode := strings.TrimSpace(strings.ToLower(req.GameMode))
	if gameMode == "" {
		gameMode = "wild_rift"
	}

	recommendation, tokens, err := gemini.AnalyzeManualDraft(
		r.Context(),
		mainRole,
		myChamp,
		enemyChamp,
		gameMode,
		lang,
		strings.TrimSpace(req.ExcludeChampions),
	)
	if err != nil {
		refundUserQueryForModel(user, reservedSource)
		log.Printf("AnalyzeManualDraft Error: %v", err)
		http.Error(w, fmt.Sprintf("Error al generar recomendación manual: %v", err), http.StatusInternalServerError)
		return
	}

	recordDraftApiUsage(user, tokens)

	resp := DraftResponse{
		Recommendation:   recommendation,
		ModelTier:        modelTier,
		AvailableQueries: user.AvailableQueries,
		ClassicQueries:   user.ClassicQueries(),
		FlakeQueries:     user.FlakeQueries(),
		AureonQueries:    user.AureonQueries(),
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

type ExtractVisionRequest struct {
	ImageBase64 string `json:"image_base64"`
	MainRole    string `json:"main_role,omitempty"`
}

type ExtractVisionResponse struct {
	Role       string   `json:"role"`
	DraftPhase string   `json:"draft_phase"`
	MyPick     string   `json:"my_pick"`
	Bans       []string `json:"bans"`
	Allies     []string `json:"allies"`
	Enemies    []string `json:"enemies"`
	TokensUsed int32    `json:"tokens_used"`
}

// ExtractDraftVision (Fase 2 - IA Local Híbrida):
// Extrae únicamente el DraftVisionJSON desde la captura de pantalla para que el celular
// ejecute el motor matemático y el SLM local sin consumir consultas de los tiers cloud.
func ExtractDraftVision(w http.ResponseWriter, r *http.Request) {
	// Límite de 4 MB por payload para proteger la RAM del servidor en horas pico (1,000+ usuarios simultáneos)
	r.Body = http.MaxBytesReader(w, r.Body, 4*1024*1024)

	var req ExtractVisionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.ImageBase64) == "" {
		http.Error(w, "image_base64 is required", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "User context missing", http.StatusInternalServerError)
		return
	}

	state, tokens, err := gemini.ExtractDraftVision(r.Context(), req.ImageBase64, req.MainRole)
	if err != nil {
		log.Printf("ExtractDraftVision Error: %v", err)
		http.Error(w, fmt.Sprintf("Error extrayendo datos del draft: %v", err), http.StatusInternalServerError)
		return
	}

	recordDraftApiUsage(user, tokens)

	resp := ExtractVisionResponse{
		Role:       state.Role,
		DraftPhase: state.DraftPhase,
		MyPick:     state.MyPick,
		Bans:       state.Bans,
		Allies:     state.Allies,
		Enemies:    state.Enemies,
		TokensUsed: tokens,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
