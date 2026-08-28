package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type User struct {
	ID           uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	GoogleID     *string   `gorm:"type:varchar(255);unique"`
	Email        string    `gorm:"type:varchar(255);not null"`
	Username     string    `gorm:"type:varchar(255)"`
	ProfilePic   string    `gorm:"type:varchar(255)"`
	PasswordHash string    `gorm:"type:varchar(255)"`
	DeviceID     string    `gorm:"type:varchar(255)"`
	SessionToken     string    `gorm:"type:varchar(255)"`
	StripeAccountID  *string   `gorm:"type:varchar(255)"` // For Creators
	StripeCustomerID *string   `gorm:"type:varchar(255)"` // For Consumers
	Role             string    `gorm:"type:varchar(50);default:'consumer'"` // 'consumer', 'entrepreneur', 'admin'
	Strikes      int       `gorm:"default:0"`
	Banned       bool      `gorm:"default:false"`
	IsPendingBan bool      `gorm:"default:false"`
	PendingBanUntil *time.Time
	ActiveGroupID *uuid.UUID `gorm:"type:uuid"` // The group the user is subscribed to
	CurrentGoal   *string    `gorm:"type:varchar(255)"` // The current short-term goal for the AI coach
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
