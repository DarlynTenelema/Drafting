package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type User struct {
	ID           uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	GoogleID     *string   `gorm:"type:varchar(255);uniqueIndex"`
	Email        string    `gorm:"type:varchar(255);not null"`
	PasswordHash string    `gorm:"type:varchar(255)"`
	SessionToken string    `gorm:"type:varchar(255)"`
	LastDraftAt          time.Time
	SubscriptionEndsAt   *time.Time
	CreatedAt            time.Time
	UpdatedAt    time.Time
	DeletedAt    gorm.DeletedAt `gorm:"index"`
}

func (user *User) BeforeCreate(tx *gorm.DB) (err error) {
	if user.ID == uuid.Nil {
		user.ID = uuid.New()
	}
	return
}
