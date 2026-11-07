package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// DonorProfile almacena el perfil del usuario en el Ranking de Donadores y los enlaces a su canal de Twitch, Kick o TikTok
type DonorProfile struct {
	ID              uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID          uuid.UUID      `gorm:"type:uuid;uniqueIndex;not null" json:"user_id"`
	DisplayName     string         `gorm:"type:varchar(120);not null" json:"display_name"`
	AvatarURL       string         `gorm:"type:varchar(500);default:''" json:"avatar_url"`
	Platform        string         `gorm:"type:varchar(40);default:'tiktok'" json:"platform"` // tiktok, twitch, kick
	ChannelHandle   string         `gorm:"type:varchar(100);default:''" json:"channel_handle"`
	ChannelURL      string         `gorm:"type:varchar(500);default:''" json:"channel_url"`
	BioMessage      string         `gorm:"type:varchar(240);default:''" json:"bio_message"`
	IsLive          bool           `gorm:"default:false;index" json:"is_live"`
	TotalDonatedUSD float64        `gorm:"type:decimal(10,2);default:0.00;index" json:"total_donated_usd"`
	DonationsCount  int            `gorm:"default:0" json:"donations_count"`
	LastDonatedAt   time.Time      `json:"last_donated_at"`
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`
}

func (d *DonorProfile) BeforeCreate(tx *gorm.DB) (err error) {
	if d.ID == uuid.Nil {
		d.ID = uuid.New()
	}
	return
}

