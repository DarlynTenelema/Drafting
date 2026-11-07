package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// AppEvent almacena los directos en vivo, torneos, sorteos y publicaciones de redes sociales para la pantalla de Eventos
type AppEvent struct {
	ID            uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	Title         string         `gorm:"type:varchar(160);not null" json:"title"`
	Subtitle      string         `gorm:"type:varchar(500);not null" json:"subtitle"`
	TitlePT       string         `gorm:"type:varchar(160);default:''" json:"title_pt,omitempty"`
	SubtitlePT    string         `gorm:"type:varchar(500);default:''" json:"subtitle_pt,omitempty"`
	TitleEN       string         `gorm:"type:varchar(160);default:''" json:"title_en,omitempty"`
	SubtitleEN    string         `gorm:"type:varchar(500);default:''" json:"subtitle_en,omitempty"`
	TitleFR       string         `gorm:"type:varchar(160);default:''" json:"title_fr,omitempty"`
	SubtitleFR    string         `gorm:"type:varchar(500);default:''" json:"subtitle_fr,omitempty"`
	Platform      string         `gorm:"type:varchar(50);not null;default:'tiktok'" json:"platform"`     // tiktok, facebook, x, discord, twitch, kick, youtube
	EventType     string         `gorm:"type:varchar(40);not null;default:'event'" json:"event_type"`    // live, event, post
	ActionURL     string         `gorm:"type:varchar(500);not null" json:"action_url"`                   // Enlace directo al stream o publicación
	BadgeText     string         `gorm:"type:varchar(64);default:'EVENTO OFICIAL'" json:"badge_text"`
	EventDateText string         `gorm:"type:varchar(80);default:''" json:"event_date_text"`
	IsLive        bool           `gorm:"default:false;index" json:"is_live"`
	Active        bool           `gorm:"default:true;index" json:"active"`
	Priority      int            `gorm:"default:5" json:"priority"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
}

func (e *AppEvent) BeforeCreate(tx *gorm.DB) (err error) {
	if e.ID == uuid.Nil {
		e.ID = uuid.New()
	}
	return
}

// SocialLinkConfig almacena los enlaces oficiales a las redes sociales de Drafting configurables en caliente
type SocialLinkConfig struct {
	ID          uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	Platform    string    `gorm:"type:varchar(50);uniqueIndex;not null" json:"platform"` // facebook, tiktok, x, discord, twitch, kick, youtube
	Name        string    `gorm:"type:varchar(80);not null" json:"name"`
	Handle      string    `gorm:"type:varchar(100);default:''" json:"handle"`
	URL         string    `gorm:"type:varchar(500);not null" json:"url"`
	Description string    `gorm:"type:varchar(255);default:''" json:"description"`
	Active      bool      `gorm:"default:true" json:"active"`
	SortOrder   int       `gorm:"default:1" json:"sort_order"`
	UpdatedAt   time.Time `json:"updated_at"`
}

func (s *SocialLinkConfig) BeforeCreate(tx *gorm.DB) (err error) {
	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	return
}

// AppVersionConfig almacena en PostgreSQL la política de versión activa para sobrevivir reinicios de servidor
type AppVersionConfig struct {
	ID                     string    `gorm:"type:varchar(32);primaryKey" json:"id"`
	LatestVersionCode      int       `gorm:"not null;default:38" json:"latest_version_code"`
	LatestVersionName      string    `gorm:"type:varchar(32);not null;default:'1.0.6'" json:"latest_version_name"`
	MinRequiredVersionCode int       `gorm:"not null;default:37" json:"min_required_version_code"`
	ForceUpdate            bool      `gorm:"default:false" json:"force_update"`
	UpdateMode             string    `gorm:"type:varchar(20);default:'flexible'" json:"update_mode"`
	ReleaseNotesES         string    `gorm:"type:text" json:"release_notes_es"`
	ReleaseNotesPT         string    `gorm:"type:text" json:"release_notes_pt"`
	ReleaseNotesEN         string    `gorm:"type:text" json:"release_notes_en"`
	ReleaseNotesFR         string    `gorm:"type:text" json:"release_notes_fr"`
	UpdatedAt              time.Time `json:"updated_at"`
}


