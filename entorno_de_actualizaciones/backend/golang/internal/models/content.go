package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Channel struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	OwnerID   uuid.UUID `gorm:"type:uuid;uniqueIndex;not null"`
	Name      string    `gorm:"type:varchar(255);not null"`
	LogoURL   string    `gorm:"type:varchar(512)"`
	Status    string    `gorm:"type:varchar(50);default:'pending'"` // pending, approved, rejected
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
	VideoURL    string    `gorm:"type:varchar(512);not null"` // YouTube or Twitch URL
	Tags        string    `gorm:"type:varchar(255)"` // Comma separated
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
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	CreatorID uuid.UUID `gorm:"type:uuid;not null;index"`
	Title     string    `gorm:"type:varchar(255);not null"`
	ImageURL  string    `gorm:"type:varchar(512);not null"`
	PriceCoin float64   `gorm:"type:decimal(10,2);not null"` // Price in GoldenCoins
	Status    string    `gorm:"type:varchar(50);default:'pending'"` // pending, approved, rejected
	CreatedAt time.Time
	UpdatedAt time.Time
}

func (f *Fanart) BeforeCreate(tx *gorm.DB) (err error) {
	if f.ID == uuid.Nil {
		f.ID = uuid.New()
	}
	return
}
