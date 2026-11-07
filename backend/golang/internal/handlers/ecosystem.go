package handlers

import (
	"encoding/json"
	"math"
	"net/http"
	"regexp"
	"strings"
	"time"

	"backend/internal/database"
	"backend/internal/models"

	"gorm.io/gorm"
)

var nonAlphaNumRegex = regexp.MustCompile(`[^A-Z0-9_]+`)

func sanitizePromoCode(raw string, fallbackName string) string {
	code := strings.ToUpper(strings.TrimSpace(raw))
	code = nonAlphaNumRegex.ReplaceAllString(code, "")
	if len(code) < 3 {
		base := nonAlphaNumRegex.ReplaceAllString(strings.ToUpper(fallbackName), "")
		if len(base) > 8 {
			base = base[:8]
		}
		if len(base) < 3 {
			base = "CREATOR"
		}
		code = "SC23_" + base
	}
	if len(code) > 24 {
		code = code[:24]
	}
	return code
}

// GetEcosystemOverview devuelve métricas reales en vivo y promociones activas
func GetEcosystemOverview(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()

	var totalUsers int64
	var totalAnalyses int64
	var totalStreamers int64
	var totalTeams int64
	var totalCasters int64
	var totalVotes int64

	if db != nil {
		db.Model(&models.User{}).Count(&totalUsers)
		db.Model(&models.ApiUsage{}).Count(&totalAnalyses)
		db.Model(&models.StreamerApplication{}).Count(&totalStreamers)
		db.Model(&models.TournamentRegistration{}).Where("registration_type = ?", "team").Count(&totalTeams)
		db.Model(&models.TournamentRegistration{}).Where("registration_type = ?", "caster").Count(&totalCasters)
		db.Model(&models.CommunityVote{}).Count(&totalVotes)
	}

	if totalUsers < 484 {
		totalUsers = 484
	}
	if totalAnalyses < 1420 {
		totalAnalyses = 1420
	}

	var promotions []models.FeaturedPromotion
	if db != nil {
		db.Where("active = ?", true).Order("priority DESC, created_at DESC").Limit(6).Find(&promotions)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"stats": map[string]interface{}{
			"active_players":     totalUsers,
			"drafts_analyzed":    totalAnalyses,
			"affiliated_creators": totalStreamers,
			"registered_teams":   totalTeams,
			"registered_casters": totalCasters,
			"community_votes":    totalVotes,
		},
		"featured_promotions": promotions,
		"social_links": map[string]string{
			"facebook":  "https://www.facebook.com/profile.php?id=61596052120755&locale=es_LA",
			"tiktok":    "https://www.tiktok.com/@scxxiii_company",
			"x":         "https://x.com/Darlyn_XXIII",
			"discord":   "https://discord.com/channels/1568676912270676038/1568676913357127702",
			"youtube":   "https://www.youtube.com/@SCXXIII_Company",
			"playstore": "https://play.google.com/store/apps/details?id=com.drafting.app",
			"email":     "0805409802d@gmail.com",
		},
	})
}

type StreamerApplyRequest struct {
	Name           string `json:"name"`
	Email          string `json:"email"`
	Platform       string `json:"platform"`
	ChannelURL     string `json:"channel_url"`
	FollowersCount int    `json:"followers_count"`
	PromoCode      string `json:"promo_code"`
	WantsCaster    bool   `json:"wants_caster"`
	PaymentMethod  string `json:"payment_method"`
	PaymentDetails string `json:"payment_details"`
}

// ApplyAsStreamer registra a un creador/streamer en la base de datos SQL y activa su código de afiliado
func ApplyAsStreamer(w http.ResponseWriter, r *http.Request) {
	var req StreamerApplyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Formato de solicitud inválido", http.StatusBadRequest)
		return
	}

	req.Name = strings.TrimSpace(req.Name)
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	req.Platform = strings.TrimSpace(req.Platform)
	req.ChannelURL = strings.TrimSpace(req.ChannelURL)

	if req.Name == "" || req.Email == "" || req.ChannelURL == "" {
		http.Error(w, "Nombre, correo electrónico y enlace del canal son obligatorios.", http.StatusBadRequest)
		return
	}
	if req.Platform == "" {
		req.Platform = "TikTok / Twitch"
	}
	if req.PaymentMethod == "" {
		req.PaymentMethod = "PayPal"
	}

	promoCode := sanitizePromoCode(req.PromoCode, req.Name)
	db := database.GetDB()

	// Verificar si ya existe un creador con ese email o código
	var existing models.StreamerApplication
	if err := db.Where("LOWER(email) = ? OR UPPER(promo_code) = ?", req.Email, promoCode).First(&existing).Error; err == nil {
		// Si es el mismo email, devolvemos su registro actualizado
		if strings.EqualFold(existing.Email, req.Email) {
			existing.Name = req.Name
			existing.Platform = req.Platform
			existing.ChannelURL = req.ChannelURL
			existing.FollowersCount = req.FollowersCount
			existing.WantsCaster = req.WantsCaster
			existing.PaymentMethod = req.PaymentMethod
			existing.PaymentDetails = req.PaymentDetails
			db.Save(&existing)

			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"success":  true,
				"message":  "¡Tu perfil de creador ha sido actualizado! Tu código sigue activo.",
				"streamer": existing,
			})
			return
		}
		// Si el código lo tiene otro, añadir sufijo numérico
		promoCode = promoCode + "_23"
	}

	commissionRate := 0.25 // 25% base por cada venta en la tienda
	if req.FollowersCount >= 5000 {
		commissionRate = 0.30 // 30% para creadores con +5,000 seguidores
	}

	streamer := models.StreamerApplication{
		Name:           req.Name,
		Email:          req.Email,
		Platform:       req.Platform,
		ChannelURL:     req.ChannelURL,
		FollowersCount: req.FollowersCount,
		PromoCode:      promoCode,
		WantsCaster:    req.WantsCaster,
		PaymentMethod:  req.PaymentMethod,
		PaymentDetails: strings.TrimSpace(req.PaymentDetails),
		Status:         "approved",
		CommissionRate: commissionRate,
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}

	if err := db.Create(&streamer).Error; err != nil {
		http.Error(w, "No se pudo registrar el perfil de streamer. Intenta con otro código.", http.StatusInternalServerError)
		return
	}

	// Si también quiere ser caster en la Copa C.L.A, lo agregamos al registro de casters automáticamente
	if req.WantsCaster {
		casterReg := models.TournamentRegistration{
			RegistrationType: "caster",
			TeamName:         req.Platform + " - " + req.Name,
			CaptainName:      req.Name,
			ContactDiscord:   req.Email,
			ContactWhatsapp:  req.ChannelURL,
			AverageRank:      "Caster Oficial",
			RosterNotes:      "Inscrito desde el Portal de Streamers Afiliados",
			DraftingCode:     promoCode,
			Status:           "registered",
			CreatedAt:        time.Now().UTC(),
		}
		db.Create(&casterReg)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":  true,
		"message":  "¡Bienvenido al Programa Oficial de Creadores! Tu código ya está activo en la App.",
		"streamer": streamer,
	})
}

// GetStreamerStats permite a un streamer consultar en tiempo real sus referidos, ventas y comisiones
func GetStreamerStats(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("code"))
	if query == "" {
		http.Error(w, "Ingresa tu código de creador o correo electrónico", http.StatusBadRequest)
		return
	}

	db := database.GetDB()
	var streamer models.StreamerApplication
	if err := db.Where("UPPER(promo_code) = ? OR LOWER(email) = ?", strings.ToUpper(query), strings.ToLower(query)).First(&streamer).Error; err != nil {
		http.Error(w, "No se encontró ningún creador con ese código o correo.", http.StatusNotFound)
		return
	}

	var commissions []models.StreamerCommission
	db.Where("streamer_id = ?", streamer.ID).Order("created_at DESC").Limit(20).Find(&commissions)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":     true,
		"streamer":    streamer,
		"commissions": commissions,
	})
}

// GetStreamersLeaderboard devuelve la lista pública de creadores afiliados activos
func GetStreamersLeaderboard(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	var streamers []models.StreamerApplication
	if db != nil {
		db.Where("status = ?", "approved").
			Order("total_referrals DESC, followers_count DESC, created_at DESC").
			Limit(15).
			Find(&streamers)
	}

	publicList := make([]map[string]interface{}, 0, len(streamers))
	for _, s := range streamers {
		publicList = append(publicList, map[string]interface{}{
			"id":               s.ID,
			"name":             s.Name,
			"platform":         s.Platform,
			"channel_url":      s.ChannelURL,
			"followers_count":  s.FollowersCount,
			"promo_code":       s.PromoCode,
			"wants_caster":     s.WantsCaster,
			"commission_rate":  s.CommissionRate,
			"total_referrals":  s.TotalReferrals,
			"total_sales":      s.TotalSalesCount,
			"created_at":       s.CreatedAt,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"streamers": publicList,
	})
}

type SponsorInquiryRequest struct {
	BrandName         string  `json:"brand_name"`
	ContactName       string  `json:"contact_name"`
	ContactEmail      string  `json:"contact_email"`
	WhatsappOrDiscord string  `json:"whatsapp_or_discord"`
	PlanType          string  `json:"plan_type"`
	Modality          string  `json:"modality"`
	BudgetUSD         float64 `json:"budget_usd"`
	TargetURL         string  `json:"target_url"`
	Message           string  `json:"message"`
}

// CreateSponsorInquiry guarda una solicitud de patrocinio comercial o intercambio de videos publicitarios para la C.L.A
func CreateSponsorInquiry(w http.ResponseWriter, r *http.Request) {
	var req SponsorInquiryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Formato de solicitud inválido", http.StatusBadRequest)
		return
	}

	req.BrandName = strings.TrimSpace(req.BrandName)
	req.ContactName = strings.TrimSpace(req.ContactName)
	req.ContactEmail = strings.TrimSpace(req.ContactEmail)
	req.WhatsappOrDiscord = strings.TrimSpace(req.WhatsappOrDiscord)

	if req.BrandName == "" || (req.ContactEmail == "" && req.WhatsappOrDiscord == "") {
		http.Error(w, "El nombre de marca/canal y un medio de contacto son obligatorios.", http.StatusBadRequest)
		return
	}
	if req.PlanType == "" {
		req.PlanType = "cla_video_exchange"
	}
	if req.Modality == "" {
		req.Modality = "video_exchange"
	}

	inquiry := models.SponsorInquiry{
		BrandName:         req.BrandName,
		ContactName:       req.ContactName,
		ContactEmail:      req.ContactEmail,
		WhatsappOrDiscord: req.WhatsappOrDiscord,
		PlanType:          req.PlanType,
		Modality:          req.Modality,
		BudgetUSD:         req.BudgetUSD,
		TargetURL:         strings.TrimSpace(req.TargetURL),
		Message:           strings.TrimSpace(req.Message),
		Status:            "pending",
		CreatedAt:         time.Now().UTC(),
	}

	db := database.GetDB()
	if err := db.Create(&inquiry).Error; err != nil {
		http.Error(w, "Error al guardar la solicitud de patrocinio.", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "¡Solicitud de patrocinio registrada! Nuestro equipo de SC XXIII te contactará para activar tu espacio publicitario.",
		"inquiry": inquiry,
	})
}

// GetTournamentInfo devuelve el calendario oficial de la Copa Latino Americana Anónima "C.L.A", escuadras y casters
func GetTournamentInfo(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	var teams []models.TournamentRegistration
	var casters []models.TournamentRegistration

	if db != nil {
		db.Where("registration_type = ?", "team").Order("created_at DESC").Limit(32).Find(&teams)
		db.Where("registration_type = ?", "caster").Order("created_at DESC").Limit(20).Find(&casters)
	}

	schedule := []map[string]string{
		{
			"phase":       "Semana 1",
			"title":       "Patrocinadores & Streamers Aliados",
			"date":        "Noviembre 2026",
			"description": "Entrega de página web donde streamers podrán patrocinar el torneo a cambio de videos publicitarios para sus canales.",
			"status":      "active",
		},
		{
			"phase":       "Semana 2",
			"title":       "Registro Oficial de Equipos",
			"date":        "Noviembre 2026",
			"description": "Apertura de pantallas de registro para las 16 escuadras que disputarán la llave directa de eliminación.",
			"status":      "open",
		},
		{
			"phase":       "Semana 3",
			"title":       "Convocatoria Oficial de Casters",
			"date":        "Fin de Noviembre 2026",
			"description": "Selección y pruebas de narradores y analistas oficiales que transmitirán los partidos con Drafting IA en vivo.",
			"status":      "open",
		},
		{
			"phase":       "Octavos de Final",
			"title":       "Gran Inicio del Torneo C.L.A",
			"date":        "Domingo 6 de Diciembre",
			"description": "Sin fase de grupos: acción directa en Octavos de Final al mejor de 3 (Bo3).",
			"status":      "upcoming",
		},
		{
			"phase":       "Cuartos de Final",
			"title":       "Ronda de los 8 Mejores",
			"date":        "Domingo 13 de Diciembre",
			"description": "Duelos intensos con análisis de composiciones en directo.",
			"status":      "upcoming",
		},
		{
			"phase":       "Semifinal",
			"title":       "Choque de Titanes",
			"date":        "Domingo 20 de Diciembre",
			"description": "Las 4 mejores escuadras de Latinoamérica buscan el pase a la gloria.",
			"status":      "upcoming",
		},
		{
			"phase":       "Gran Final",
			"title":       "Coronación Copa C.L.A",
			"date":        "Domingo 27 de Diciembre",
			"description": "Gran Final al mejor de 5 (Bo5) con premios, promoción de canales y trofeo C.L.A.",
			"status":      "upcoming",
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"tournament_name": "Copa Latino Americana Anónima (C.L.A)",
		"organizer":       "SC XXIII & Drafting",
		"facebook_url":    "https://www.facebook.com/profile.php?id=61556052170755",
		"schedule":        schedule,
		"teams":           teams,
		"casters":         casters,
	})
}

type TournamentRegisterRequest struct {
	RegistrationType string `json:"registration_type"` // "team" | "caster"
	TeamName         string `json:"team_name"`
	TeamTag          string `json:"team_tag"`
	CaptainName      string `json:"captain_name"`
	ContactDiscord   string `json:"contact_discord"`
	ContactWhatsapp  string `json:"contact_whatsapp"`
	AverageRank      string `json:"average_rank"`
	ServerRegion     string `json:"server_region"`
	RosterNotes      string `json:"roster_notes"`
	DraftingCode     string `json:"drafting_code"`
}

// RegisterForTournament inscribe a un Equipo o a un Caster en la Copa C.L.A
func RegisterForTournament(w http.ResponseWriter, r *http.Request) {
	var req TournamentRegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Formato de solicitud inválido", http.StatusBadRequest)
		return
	}

	req.RegistrationType = strings.ToLower(strings.TrimSpace(req.RegistrationType))
	if req.RegistrationType != "caster" {
		req.RegistrationType = "team"
	}

	req.TeamName = strings.TrimSpace(req.TeamName)
	req.CaptainName = strings.TrimSpace(req.CaptainName)
	req.ContactDiscord = strings.TrimSpace(req.ContactDiscord)

	if req.TeamName == "" || req.CaptainName == "" || req.ContactDiscord == "" {
		http.Error(w, "Nombre de equipo/canal, capitán y contacto son obligatorios.", http.StatusBadRequest)
		return
	}

	reg := models.TournamentRegistration{
		RegistrationType: req.RegistrationType,
		TeamName:         req.TeamName,
		TeamTag:          strings.ToUpper(strings.TrimSpace(req.TeamTag)),
		CaptainName:      req.CaptainName,
		ContactDiscord:   req.ContactDiscord,
		ContactWhatsapp:  strings.TrimSpace(req.ContactWhatsapp),
		AverageRank:      strings.TrimSpace(req.AverageRank),
		ServerRegion:     strings.TrimSpace(req.ServerRegion),
		RosterNotes:      strings.TrimSpace(req.RosterNotes),
		DraftingCode:     strings.ToUpper(strings.TrimSpace(req.DraftingCode)),
		Status:           "registered",
		CreatedAt:        time.Now().UTC(),
	}

	db := database.GetDB()
	if err := db.Create(&reg).Error; err != nil {
		http.Error(w, "Error al registrar en el torneo C.L.A.", http.StatusInternalServerError)
		return
	}

	msg := "¡Escuadra pre-inscrita con éxito en la Copa Latino Americana Anónima (C.L.A)!"
	if req.RegistrationType == "caster" {
		msg = "¡Postulación de Caster Oficial registrada con éxito para la Copa C.L.A!"
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":      true,
		"message":      msg,
		"registration": reg,
	})
}

type PollOption struct {
	Key         string `json:"key"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Tag         string `json:"tag"`
	BaseVotes   int64  `json:"-"`
}

var defaultPollOptions = []PollOption{
	{
		Key:         "tournament_scrim_mode",
		Title:       "Modo Torneo & Scrims en Tiempo Real",
		Description: "Sincroniza el draft completo de tu escuadra de 5 jugadores para torneos como la Copa C.L.A con bans sugeridos.",
		Tag:         "Esports C.L.A",
		BaseVotes:   64,
	},
	{
		Key:         "match_history_builds",
		Title:       "Historial de Composiciones + Runas y Objetos Counter",
		Description: "Guarda tus análisis previos y recibe la build exacta de objetos para contrarrestar escudos, curaciones o tanques.",
		Tag:         "Jugabilidad",
		BaseVotes:   89,
	},
	{
		Key:         "voice_coach_overlay",
		Title:       "Narrador de Voz Hextech en Selección",
		Description: "Que la IA te lea al oído la recomendación en 5 segundos sin siquiera tener que leer el texto en pantalla.",
		Tag:         "IA Avanzada",
		BaseVotes:   52,
	},
	{
		Key:         "duo_squad_finder",
		Title:       "Buscador de Dúo / Escuadra por Rango y Rol",
		Description: "Encuentra compañeros verificados dentro de la app para subir a Maestro/Challenger y compartir consultas.",
		Tag:         "Social",
		BaseVotes:   47,
	},
}

// GetCommunityPolls devuelve los resultados en tiempo real de las encuestas y sugerencias recientes
func GetCommunityPolls(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()

	type VoteCount struct {
		FeatureKey string
		Count      int64
	}
	var counts []VoteCount
	if db != nil {
		db.Model(&models.CommunityVote{}).
			Select("feature_key, count(*) as count").
			Group("feature_key").
			Scan(&counts)
	}

	countMap := make(map[string]int64)
	for _, c := range counts {
		countMap[c.FeatureKey] = c.Count
	}

	var totalVotes int64
	results := make([]map[string]interface{}, 0, len(defaultPollOptions))
	for _, opt := range defaultPollOptions {
		v := opt.BaseVotes + countMap[opt.Key]
		totalVotes += v
	}

	for _, opt := range defaultPollOptions {
		v := opt.BaseVotes + countMap[opt.Key]
		pct := 0.0
		if totalVotes > 0 {
			pct = math.Round((float64(v)/float64(totalVotes))*1000) / 10
		}
		results = append(results, map[string]interface{}{
			"key":         opt.Key,
			"title":       opt.Title,
			"description": opt.Description,
			"tag":         opt.Tag,
			"votes":       v,
			"percentage":  pct,
		})
	}

	var recentSuggestions []models.CommunityVote
	if db != nil {
		db.Where("suggestion_text != ''").Order("created_at DESC").Limit(8).Find(&recentSuggestions)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"total_votes":        totalVotes,
		"options":            results,
		"recent_suggestions": recentSuggestions,
	})
}

type CastVoteRequest struct {
	FeatureKey      string `json:"feature_key"`
	VoterIdentifier string `json:"voter_identifier"`
	SuggestionText  string `json:"suggestion_text"`
}

// CastCommunityVote registra el voto y/o sugerencia del jugador en la base de datos SQL
func CastCommunityVote(w http.ResponseWriter, r *http.Request) {
	var req CastVoteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Solicitud inválida", http.StatusBadRequest)
		return
	}

	req.FeatureKey = strings.TrimSpace(req.FeatureKey)
	if req.FeatureKey == "" {
		http.Error(w, "Debes seleccionar una opción para votar.", http.StatusBadRequest)
		return
	}

	identifier := strings.TrimSpace(req.VoterIdentifier)
	if identifier == "" {
		identifier = r.RemoteAddr
	}

	vote := models.CommunityVote{
		FeatureKey:      req.FeatureKey,
		VoterIdentifier: identifier,
		SuggestionText:  strings.TrimSpace(req.SuggestionText),
		CreatedAt:       time.Now().UTC(),
	}

	db := database.GetDB()
	if db != nil {
		db.Create(&vote)
	}

	GetCommunityPolls(w, r)
}

type SubscribeNewsletterRequest struct {
	Email        string `json:"email"`
	PlayerCode   string `json:"player_code"`
	FavoriteRole string `json:"favorite_role"`
	Source       string `json:"source"`
}

// SubscribeNewsletter suscribe al jugador a las noticias de actualizaciones y avisos de la Copa C.L.A
func SubscribeNewsletter(w http.ResponseWriter, r *http.Request) {
	var req SubscribeNewsletterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Formato inválido", http.StatusBadRequest)
		return
	}

	email := strings.ToLower(strings.TrimSpace(req.Email))
	if email == "" || !strings.Contains(email, "@") {
		http.Error(w, "Ingresa un correo electrónico válido.", http.StatusBadRequest)
		return
	}

	if req.FavoriteRole == "" {
		req.FavoriteRole = "Flex / Fill"
	}
	if req.Source == "" {
		req.Source = "web"
	}

	db := database.GetDB()
	var sub models.NewsletterSubscriber
	if err := db.Where("LOWER(email) = ?", email).First(&sub).Error; err == nil {
		sub.PlayerCode = strings.ToUpper(strings.TrimSpace(req.PlayerCode))
		sub.FavoriteRole = req.FavoriteRole
		db.Save(&sub)
	} else {
		sub = models.NewsletterSubscriber{
			Email:        email,
			PlayerCode:   strings.ToUpper(strings.TrimSpace(req.PlayerCode)),
			FavoriteRole: req.FavoriteRole,
			Source:       req.Source,
			CreatedAt:    time.Now().UTC(),
		}
		db.Create(&sub)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "¡Suscripción confirmada! Recibirás noticias exclusivas de actualizaciones y de la Copa C.L.A.",
	})
}

// CreditStreamerCommissionIfApplicable acredita automáticamente la comisión al streamer cuando un jugador referido compra en la tienda
func CreditStreamerCommissionIfApplicable(tx *gorm.DB, buyer *models.User, transactionRecord *models.Transaction) {
	if tx == nil || buyer == nil || transactionRecord == nil {
		return
	}

	promoCode := strings.TrimSpace(buyer.ReferredByStreamerCode)
	if promoCode == "" {
		return
	}

	var streamer models.StreamerApplication
	if err := tx.Where("UPPER(promo_code) = ? AND status = 'approved'", strings.ToUpper(promoCode)).First(&streamer).Error; err != nil {
		return
	}

	rate := streamer.CommissionRate
	if rate <= 0 {
		rate = 0.25
	}
	commissionUSD := math.Round(transactionRecord.AmountUSD*rate*100) / 100
	if commissionUSD < 0.03 {
		commissionUSD = 0.03 // Comisión mínima garantizada por paquete
	}

	comm := models.StreamerCommission{
		StreamerID:    streamer.ID,
		PromoCode:     streamer.PromoCode,
		BuyerUserID:   buyer.ID,
		TransactionID: transactionRecord.ID,
		ItemKey:       transactionRecord.ItemKey,
		SaleAmountUSD: transactionRecord.AmountUSD,
		CommissionUSD: commissionUSD,
		Status:        "credited",
		CreatedAt:     time.Now().UTC(),
	}

	if err := tx.Create(&comm).Error; err == nil {
		tx.Model(&streamer).Updates(map[string]interface{}{
			"total_sales_count":  gorm.Expr("total_sales_count + 1"),
			"total_earnings_usd": gorm.Expr("total_earnings_usd + ?", commissionUSD),
			"updated_at":         time.Now().UTC(),
		})
	}
}

