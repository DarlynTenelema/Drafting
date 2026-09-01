package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Channel struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	OwnerID   uuid.UUID `gorm:"type:uuid;unique;not null"`
	Name        string    `gorm:"type:varchar(255);not null"`
	Description string    `gorm:"type:text"`
	LogoURL     string    `gorm:"type:varchar(512)"`
	BannerURL   string    `gorm:"type:varchar(512)"`
	Status    string    `gorm:"type:varchar(50);default:'pending'"` // pending, approved, pending_verification, rejected
	Verified  bool      `gorm:"default:false"`
	SubscriberCount int `gorm:"default:0"`
	CreatedAt time.Time
	UpdatedAt time.Time
}

func (c *Channel) BeforeCreate(tx *gorm.DB) (err error) {
	if c.ID == uuid.Nil {
		c.ID = uuid.New()
	}
	return
}

type VideoEmbed struct {
	ID          uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	ChannelID   uuid.UUID `gorm:"type:uuid;not null;index"`
	Title       string    `gorm:"type:varchar(255);not null"`
	Description string    `gorm:"type:text"`
	VideoURL    string    `gorm:"type:varchar(512);not null;unique"` // YouTube or Twitch URL. Unique to prevent re-uploads
	Tags        string    `gorm:"type:varchar(255)"` // Comma separated
	Views       int       `gorm:"default:0"`
	Status      string    `gorm:"type:varchar(50);default:'pending'"` // pending, approved, rejected
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

func (v *VideoEmbed) BeforeCreate(tx *gorm.DB) (err error) {
	if v.ID == uuid.Nil {
		v.ID = uuid.New()
	}
	return
}

type Fanart struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	CreatorID uuid.UUID `gorm:"type:uuid;not null;index" json:"creator_id"`
	Title     string    `gorm:"type:varchar(255);not null" json:"title"`
	ImageURL  string    `gorm:"type:varchar(512);not null" json:"image_url"`
	PriceEssence float64   `gorm:"type:decimal(10,2);not null" json:"price_essence"` // Price in Blue Essences
	Status    string    `gorm:"type:varchar(50);default:'pending';index" json:"status"` // pending, approved, rejected
	Tags      string    `gorm:"type:varchar(255)" json:"tags"` // Comma separated
	Likes     int       `gorm:"default:0" json:"likes"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (f *Fanart) BeforeCreate(tx *gorm.DB) (err error) {
	if f.ID == uuid.Nil {
		f.ID = uuid.New()
	}
	return
}
