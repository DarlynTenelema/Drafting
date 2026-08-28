package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Report struct {
	ID              uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	ReporterID      uuid.UUID `gorm:"type:uuid;not null;index"`
	Type            string    `gorm:"type:varchar(50);not null"` // "bug", "inappropriate_content", "price_adjustment"
	Description     string    `gorm:"type:text;not null"`
	ImageURL        string    `gorm:"type:varchar(512)"`
	RelatedEntityID *uuid.UUID `gorm:"type:uuid"` // E.g., FanartID, VideoEmbedID if applicable
	Status          string    `gorm:"type:varchar(50);default:'open'"` // open, reviewed, resolved, rejected
	AdminNotes      string    `gorm:"type:text"`
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

func (r *Report) BeforeCreate(tx *gorm.DB) (err error) {
	if r.ID == uuid.Nil {
		r.ID = uuid.New()
	}
	return
}

type IdentityVerification struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	ChannelID uuid.UUID `gorm:"type:uuid;not null;index"`
	ProofURL  string    `gorm:"type:varchar(512);not null"` // Video MP4 or YouTube unlisted link
	Status    string    `gorm:"type:varchar(50);default:'pending'"` // pending, approved, rejected
	CreatedAt time.Time
	UpdatedAt time.Time
}

func (iv *IdentityVerification) BeforeCreate(tx *gorm.DB) (err error) {
	if iv.ID == uuid.Nil {
		iv.ID = uuid.New()
	}
	return
}

type ContentReport struct {
	ID         uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	VideoID    uuid.UUID `gorm:"type:uuid;not null;index"`
	ReporterID uuid.UUID `gorm:"type:uuid;not null;index"`
	Reason     string    `gorm:"type:varchar(255);not null"` // "Falsificación de identidad", "Contenido Inapropiado", etc
	ProofURL   string    `gorm:"type:varchar(512)"`          // Optional, required if identity theft
	Status     string    `gorm:"type:varchar(50);default:'pending'"` // pending, resolved, rejected
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

func (cr *ContentReport) BeforeCreate(tx *gorm.DB) (err error) {
	if cr.ID == uuid.Nil {
		cr.ID = uuid.New()
	}
	return
}
