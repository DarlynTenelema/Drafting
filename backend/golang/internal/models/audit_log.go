package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type AuditLog struct {
	ID        uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	AdminID   uuid.UUID      `gorm:"type:uuid;not null" json:"admin_id"`
	Action    string         `gorm:"type:varchar(255);not null" json:"action"`
	TargetID  *string        `gorm:"type:varchar(255)" json:"target_id"`
	Details   string         `gorm:"type:jsonb" json:"details"`
	CreatedAt time.Time      `json:"created_at"`
}

func (log *AuditLog) BeforeCreate(tx *gorm.DB) (err error) {
	if log.ID == uuid.Nil {
		log.ID = uuid.New()
	}
	return
}
