package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type CreatorProfile struct {
	ID         uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	UserID     uuid.UUID `gorm:"type:uuid;unique;not null"`
	ArtistName string    `gorm:"type:varchar(255);unique;not null"`
	Tags       string    `gorm:"type:varchar(255)"` // comma-separated, max 5 tags
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

func (c *CreatorProfile) BeforeCreate(tx *gorm.DB) (err error) {
	if c.ID == uuid.Nil {
		c.ID = uuid.New()
	}
	return
}
