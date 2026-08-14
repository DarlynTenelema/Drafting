package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type ApiUsage struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	UserID    uuid.UUID `gorm:"type:uuid;not null;index"`
	CreatedAt time.Time
}

func (apiUsage *ApiUsage) BeforeCreate(tx *gorm.DB) (err error) {
	if apiUsage.ID == uuid.Nil {
		apiUsage.ID = uuid.New()
	}
	return
}
