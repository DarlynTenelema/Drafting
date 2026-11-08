package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
	"backend/internal/notifications"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

const AuthorizedAdminEmail = "0805409802d@gmail.com"

var seedEventsMutex sync.Mutex

func normalizeExternalURL(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	lower := strings.ToLower(trimmed)
	if strings.HasPrefix(lower, "http://") || strings.HasPrefix(lower, "https://") || strings.HasPrefix(lower, "market://") {
		return trimmed
	}
	return "https://" + strings.TrimLeft(trimmed, "/")
}

func defaultSocialLinks() []models.SocialLinkConfig {
	return []models.SocialLinkConfig{
		{
			Platform:    "tiktok",
			Name:        "TikTok Oficial",
			Handle:      "@scxxiii_company",
			URL:         "https://www.tiktok.com/@scxxiii_company",
			Description: "Directos, clips de composiciones Challenger y sorteos semanales",
			Active:      true,
			SortOrder:   1,
			UpdatedAt:   time.Now().UTC(),
		},
		{
			Platform:    "facebook",
			Name:        "Facebook Oficial",
			Handle:      "SC XXIII Company",
			URL:         "https://www.facebook.com/profile.php?id=61596052120755&locale=es_LA",
			Description: "Página oficial de noticias, torneos Copa C.L.A y transmisiones",
			Active:      true,
			SortOrder:   2,
			UpdatedAt:   time.Now().UTC(),
		},
		{
			Platform:    "youtube",
			Name:        "YouTube Oficial",
			Handle:      "@SCXXIII_Company",
			URL:         "https://www.youtube.com/@SCXXIII_Company",
			Description: "Videos oficiales, guías de Draft con IA y resúmenes de torneos",
			Active:      true,
			SortOrder:   3,
			UpdatedAt:   time.Now().UTC(),
		},
		{
			Platform:    "x",
			Name:        "X (Twitter)",
			Handle:      "@Darlyn_XXIII",
			URL:         "https://x.com/Darlyn_XXIII",
			Description: "Actualizaciones al minuto, noticias y anuncios oficiales",
			Active:      true,
			SortOrder:   4,
			UpdatedAt:   time.Now().UTC(),
		},
		{
			Platform:    "discord",
			Name:        "Comunidad Discord",
			Handle:      "SC XXIII & Drafting",
			URL:         "https://discord.com/channels/1568676912270676038/1568676913357127702",
			Description: "Únete al servidor oficial, busca escuadra y participa en eventos",
			Active:      true,
			SortOrder:   5,
			UpdatedAt:   time.Now().UTC(),
		},
	}
}

func localizeSocialName(platform, defaultName, lang string) string {
	p := strings.ToLower(strings.TrimSpace(platform))
	switch lang {
	case "pt":
		switch p {
		case "tiktok":
			return "TikTok Oficial"
		case "facebook":
			return "Facebook Oficial"
		case "youtube":
			return "YouTube Oficial"
		case "x", "twitter":
			return "X (Twitter)"
		case "discord":
			return "Comunidade Discord"
		}
	case "en":
		switch p {
		case "tiktok":
			return "Official TikTok"
		case "facebook":
			return "Official Facebook"
		case "youtube":
			return "Official YouTube"
		case "x", "twitter":
			return "X (Twitter)"
		case "discord":
			return "Discord Community"
		}
	case "fr":
		switch p {
		case "tiktok":
			return "TikTok Officiel"
		case "facebook":
			return "Facebook Officiel"
		case "youtube":
			return "YouTube Officiel"
		case "x", "twitter":
			return "X (Twitter)"
		case "discord":
			return "Communauté Discord"
		}
	}
	return defaultName
}

func defaultSeedEvents() []models.AppEvent {
	now := time.Now().UTC()
	return []models.AppEvent{
		{
			Title:         "Directos & Sorteos en TikTok Oficial (@scxxiii_company)",
			Subtitle:      "Síguenos en TikTok para enterarte cuando prendamos directo jugando con suscriptores y regalando paquetes de consultas.",
			TitlePT:       "Lives & Sorteios no TikTok Oficial (@scxxiii_company)",
			SubtitlePT:    "Siga-nos no TikTok para saber quando entrarmos ao vivo jogando com inscritos e sorteando pacotes de consultas.",
			TitleEN:       "Official TikTok Live Streams & Giveaways (@scxxiii_company)",
			SubtitleEN:    "Follow us on TikTok to get notified when we go live playing with viewers and giving away query packs.",
			TitleFR:       "Directs TikTok & Cadeaux Officiels (@scxxiii_company)",
			SubtitleFR:    "Suivez-nous sur TikTok pour être averti de nos lives avec les abonnés et gagner des packs de requêtes.",
			Platform:      "tiktok",
			EventType:     "event",
			ActionURL:     "https://www.tiktok.com/@scxxiii_company",
			BadgeText:     "TIKTOK OFICIAL",
			EventDateText: "Toda la semana",
			IsLive:        false,
			Active:        true,
			Priority:      10,
			CreatedAt:     now,
			UpdatedAt:     now,
		},
		{
			Title:         "Página Oficial de Facebook • Noticias & Eventos",
			Subtitle:      "Sigue todas las transmisiones en directo, anuncios de torneos y sorteos especiales en nuestra página oficial de Facebook.",
			TitlePT:       "Página Oficial do Facebook • Notícias & Eventos",
			SubtitlePT:    "Acompanhe todas as transmissões ao vivo, anúncios de torneios e sorteios especiais na nossa página oficial do Facebook.",
			TitleEN:       "Official Facebook Page • News & Events",
			SubtitleEN:    "Follow all live broadcasts, tournament announcements, and special giveaways on our official Facebook page.",
			TitleFR:       "Page Facebook Officielle • Actualités & Événements",
			SubtitleFR:    "Suivez toutes les diffusions en direct, annonces de tournois et cadeaux sur notre page Facebook officielle.",
			Platform:      "facebook",
			EventType:     "event",
			ActionURL:     "https://www.facebook.com/profile.php?id=61596052120755&locale=es_LA",
			BadgeText:     "FACEBOOK OFICIAL",
			EventDateText: "En Vivo & Noticias",
			IsLive:        false,
			Active:        true,
			Priority:      9,
			CreatedAt:     now,
			UpdatedAt:     now,
		},
		{
			Title:         "Canal Oficial de YouTube (@SCXXIII_Company)",
			Subtitle:      "Suscríbete a nuestro canal de YouTube para ver análisis avanzados, eventos y contenido exclusivo de Drafting.",
			TitlePT:       "Canal Oficial do YouTube (@SCXXIII_Company)",
			SubtitlePT:    "Inscreva-se no nosso canal do YouTube para ver análises avançadas, eventos e conteúdo exclusivo do Drafting.",
			TitleEN:       "Official YouTube Channel (@SCXXIII_Company)",
			SubtitleEN:    "Subscribe to our YouTube channel for advanced draft analysis, events, and exclusive content.",
			TitleFR:       "Chaîne YouTube Officielle (@SCXXIII_Company)",
			SubtitleFR:    "Abonnez-vous à notre chaîne YouTube pour des analyses avancées, des événements et du contenu exclusif.",
			Platform:      "youtube",
			EventType:     "post",
			ActionURL:     "https://www.youtube.com/@SCXXIII_Company",
			BadgeText:     "NUEVOS VIDEOS",
			EventDateText: "Canal Oficial",
			IsLive:        false,
			Active:        true,
			Priority:      8,
			CreatedAt:     now,
			UpdatedAt:     now,
		},
		{
			Title:         "Servidor Oficial de Discord • Comunidad SC XXIII",
			Subtitle:      "Encuentra compañeros para subir de rango, comparte tu código de referido y entérate antes que nadie de cada actualización.",
			TitlePT:       "Servidor Oficial do Discord • Comunidade SC XXIII",
			SubtitlePT:    "Encontre parceiros para subir de elo, compartilhe seu código e fique por dentro de todas as novidades.",
			TitleEN:       "Official Discord Server • SC XXIII Community",
			SubtitleEN:    "Find duo/squad partners to climb ranks, share your referral code, and get instant update alerts.",
			TitleFR:       "Serveur Discord Officiel • Communauté SC XXIII",
			SubtitleFR:    "Trouvez des coéquipiers pour monter en rang, partagez votre code et recevez toutes les annonces.",
			Platform:      "discord",
			EventType:     "event",
			ActionURL:     "https://discord.com/channels/1568676912270676038/1568676913357127702",
			BadgeText:     "COMUNIDAD ACTIVA",
			EventDateText: "Abierto 24/7",
			IsLive:        false,
			Active:        true,
			Priority:      7,
			CreatedAt:     now,
			UpdatedAt:     now,
		},
	}
}

func ensureDefaultHubSeeded(db *gorm.DB) {
	if db == nil {
		return
	}
	seedEventsMutex.Lock()
	defer seedEventsMutex.Unlock()

	var socialCount int64
	if err := db.Model(&models.SocialLinkConfig{}).Count(&socialCount).Error; err == nil && socialCount == 0 {
		for _, link := range defaultSocialLinks() {
			db.Create(&link)
		}
	}

	var eventCount int64
	if err := db.Model(&models.AppEvent{}).Count(&eventCount).Error; err == nil && eventCount == 0 {
		for _, ev := range defaultSeedEvents() {
			db.Create(&ev)
		}
	}
}

// GetEventsHub devuelve el estado de directo actual, la lista de eventos/noticias y las redes sociales oficiales
func GetEventsHub(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	rawLang := strings.TrimSpace(r.URL.Query().Get("lang"))
	if rawLang == "" {
		rawLang = strings.TrimSpace(r.Header.Get("Accept-Language"))
	}
	lang := normalizeAppLanguage(rawLang)

	ensureDefaultHubSeeded(db)

	var socialLinks []models.SocialLinkConfig
	if db != nil {
		db.Where("active = ?", true).Order("sort_order ASC").Find(&socialLinks)
	}
	if len(socialLinks) == 0 {
		socialLinks = defaultSocialLinks()
	}

	formattedSocials := make([]map[string]interface{}, 0, len(socialLinks))
	for _, s := range socialLinks {
		formattedSocials = append(formattedSocials, map[string]interface{}{
			"id":          s.ID,
			"platform":    s.Platform,
			"name":        localizeSocialName(s.Platform, s.Name, lang),
			"handle":      s.Handle,
			"url":         normalizeExternalURL(s.URL),
			"description": s.Description,
			"active":      s.Active,
			"sort_order":  s.SortOrder,
			"updated_at":  s.UpdatedAt,
		})
	}

	var events []models.AppEvent
	if db != nil {
		db.Where("active = ?", true).Order("is_live DESC, priority DESC, updated_at DESC").Limit(25).Find(&events)
	}
	if len(events) == 0 {
		events = defaultSeedEvents()
	}

	// Localizar títulos y subtítulos según el idioma del jugador
	formattedEvents := make([]map[string]interface{}, 0, len(events))
	var liveNowEvent map[string]interface{}

	for _, ev := range events {
		title := ev.Title
		subtitle := ev.Subtitle

		switch lang {
		case "pt":
			if ev.TitlePT != "" {
				title = ev.TitlePT
			}
			if ev.SubtitlePT != "" {
				subtitle = ev.SubtitlePT
			}
		case "en":
			if ev.TitleEN != "" {
				title = ev.TitleEN
			}
			if ev.SubtitleEN != "" {
				subtitle = ev.SubtitleEN
			}
		case "fr":
			if ev.TitleFR != "" {
				title = ev.TitleFR
			}
			if ev.SubtitleFR != "" {
				subtitle = ev.SubtitleFR
			}
		}

		item := map[string]interface{}{
			"id":              ev.ID,
			"title":           title,
			"subtitle":        subtitle,
			"platform":        ev.Platform,
			"event_type":      ev.EventType,
			"action_url":      normalizeExternalURL(ev.ActionURL),
			"badge_text":      ev.BadgeText,
			"event_date_text": ev.EventDateText,
			"is_live":         ev.IsLive,
			"priority":        ev.Priority,
			"updated_at":      ev.UpdatedAt,
		}
		formattedEvents = append(formattedEvents, item)

		if ev.IsLive && liveNowEvent == nil {
			liveNowEvent = item
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"is_live_now":  liveNowEvent != nil,
		"live_now":     liveNowEvent,
		"events":       formattedEvents,
		"social_links": formattedSocials,
	})
}

type ManageEventRequest struct {
	Action        string `json:"action"` // "upsert_event" | "stop_all_live" | "delete_event" | "update_social"
	EventID       string `json:"event_id,omitempty"`
	Title         string `json:"title,omitempty"`
	Subtitle      string `json:"subtitle,omitempty"`
	TitlePT       string `json:"title_pt,omitempty"`
	SubtitlePT    string `json:"subtitle_pt,omitempty"`
	TitleEN       string `json:"title_en,omitempty"`
	SubtitleEN    string `json:"subtitle_en,omitempty"`
	TitleFR       string `json:"title_fr,omitempty"`
	SubtitleFR    string `json:"subtitle_fr,omitempty"`
	Platform      string `json:"platform,omitempty"`
	EventType     string `json:"event_type,omitempty"`
	ActionURL     string `json:"action_url,omitempty"`
	BadgeText     string `json:"badge_text,omitempty"`
	EventDateText string `json:"event_date_text,omitempty"`
	IsLive        bool   `json:"is_live"`
	Priority      int    `json:"priority,omitempty"`
	SocialHandle  string `json:"social_handle,omitempty"`
}

// ManageEventsHub permite EXCLUSIVAMENTE a la cuenta 0805409802d@gmail.com gestionar directos, eventos y redes sociales
func ManageEventsHub(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "No autenticado", http.StatusUnauthorized)
		return
	}

	// Restricción estricta: NINGUNA otra cuenta aparte de 0805409802d@gmail.com tiene acceso a este panel
	if !strings.EqualFold(strings.TrimSpace(user.Email), AuthorizedAdminEmail) {
		http.Error(w, "Acceso denegado: este panel de control es exclusivo del administrador principal.", http.StatusForbidden)
		return
	}

	var req ManageEventRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Solicitud inválida", http.StatusBadRequest)
		return
	}

	db := database.GetDB()
	if db == nil {
		http.Error(w, "Base de datos no disponible", http.StatusInternalServerError)
		return
	}

	// Garantizar que los datos semilla existan antes de insertar/editar para no ocultar las demás redes o eventos
	ensureDefaultHubSeeded(db)

	action := strings.ToLower(strings.TrimSpace(req.Action))

	switch action {
	case "stop_all_live":
		db.Model(&models.AppEvent{}).Where("is_live = ?", true).Updates(map[string]interface{}{
			"is_live":    false,
			"updated_at": time.Now().UTC(),
		})
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": "Todos los avisos de directo en vivo han sido finalizados.",
		})
		return

	case "delete_event":
		if req.EventID != "" {
			db.Where("id = ?", req.EventID).Delete(&models.AppEvent{})
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": "Evento eliminado correctamente.",
		})
		return

	case "update_social":
		platform := strings.ToLower(strings.TrimSpace(req.Platform))
		url := normalizeExternalURL(req.ActionURL)
		if platform == "" || url == "" {
			http.Error(w, "Plataforma y URL son obligatorias.", http.StatusBadRequest)
			return
		}
		var link models.SocialLinkConfig
		if err := db.Where("LOWER(platform) = ?", platform).First(&link).Error; err == nil {
			link.URL = url
			if strings.TrimSpace(req.SocialHandle) != "" {
				link.Handle = strings.TrimSpace(req.SocialHandle)
			}
			if strings.TrimSpace(req.Title) != "" {
				link.Name = strings.TrimSpace(req.Title)
			}
			if strings.TrimSpace(req.Subtitle) != "" {
				link.Description = strings.TrimSpace(req.Subtitle)
			}
			link.Active = true
			link.UpdatedAt = time.Now().UTC()
			db.Save(&link)
		} else {
			name := strings.TrimSpace(req.Title)
			if name == "" {
				name = strings.ToUpper(platform[:1]) + platform[1:]
			}
			link = models.SocialLinkConfig{
				Platform:    platform,
				Name:        name,
				Handle:      strings.TrimSpace(req.SocialHandle),
				URL:         url,
				Description: strings.TrimSpace(req.Subtitle),
				Active:      true,
				SortOrder:   10,
				UpdatedAt:   time.Now().UTC(),
			}
			db.Create(&link)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success":     true,
			"message":     "Red social actualizada correctamente.",
			"social_link": link,
		})
		return

	default:
		title := strings.TrimSpace(req.Title)
		subtitle := strings.TrimSpace(req.Subtitle)
		actionURL := normalizeExternalURL(req.ActionURL)
		platform := strings.ToLower(strings.TrimSpace(req.Platform))
		if platform == "" {
			platform = "tiktok"
		}
		if title == "" || actionURL == "" {
			http.Error(w, "Título y enlace (URL) son obligatorios.", http.StatusBadRequest)
			return
		}
		if subtitle == "" {
			if req.IsLive {
				subtitle = "¡Estamos transmitiendo en vivo ahora mismo! Toca esta tarjeta para entrar directo a la transmisión."
			} else {
				subtitle = "Toca para ver la publicación o participar en el evento oficial."
			}
		}

		badge := strings.TrimSpace(req.BadgeText)
		if badge == "" {
			if req.IsLive {
				badge = "🔴 EN DIRECTO AHORA"
			} else {
				badge = "EVENTO OFICIAL"
			}
		}
		dateText := strings.TrimSpace(req.EventDateText)
		if dateText == "" {
			if req.IsLive {
				dateText = "EN VIVO AHORA"
			} else {
				dateText = time.Now().UTC().Format("02 Jan 2006")
			}
		}

		eventType := strings.TrimSpace(req.EventType)
		if eventType == "" {
			if req.IsLive {
				eventType = "live"
			} else {
				eventType = "event"
			}
		}

		priority := req.Priority
		if priority <= 0 {
			if req.IsLive {
				priority = 100
			} else {
				priority = 10
			}
		}

		if req.IsLive {
			db.Model(&models.AppEvent{}).Where("is_live = ?", true).Updates(map[string]interface{}{
				"is_live": false,
			})
		}

		var ev models.AppEvent
		if req.EventID != "" {
			if parsedID, err := uuid.Parse(req.EventID); err == nil {
				db.Where("id = ?", parsedID).First(&ev)
			}
		}

		ev.Title = title
		ev.Subtitle = subtitle
		ev.TitlePT = strings.TrimSpace(req.TitlePT)
		ev.SubtitlePT = strings.TrimSpace(req.SubtitlePT)
		ev.TitleEN = strings.TrimSpace(req.TitleEN)
		ev.SubtitleEN = strings.TrimSpace(req.SubtitleEN)
		ev.TitleFR = strings.TrimSpace(req.TitleFR)
		ev.SubtitleFR = strings.TrimSpace(req.SubtitleFR)
		ev.Platform = platform
		ev.EventType = eventType
		ev.ActionURL = actionURL
		ev.BadgeText = badge
		ev.EventDateText = dateText
		ev.IsLive = req.IsLive
		ev.Active = true
		ev.Priority = priority
		ev.UpdatedAt = time.Now().UTC()

		if ev.ID == uuid.Nil {
			ev.CreatedAt = time.Now().UTC()
			db.Create(&ev)
		} else {
			db.Save(&ev)
		}

		// Si es un directo en vivo o evento destacado, despachar Notificación Push masiva a todos los usuarios
		if ev.IsLive {
			notifications.SendLiveStreamPush(
				ev.Title,
				ev.Subtitle,
				ev.ActionURL,
				ev.Platform,
				true,
			)
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": "¡Evento / Directo publicado en vivo para todos los jugadores de la app!",
			"event":   ev,
		})
	}
}
