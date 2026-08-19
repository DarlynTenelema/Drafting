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
