package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Group struct {
	ID              uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	OwnerID         uuid.UUID `gorm:"type:uuid;not null;index"`
	Name            string    `gorm:"type:varchar(255);not null"`
	Description     string    `gorm:"type:text"`
	SubscriptionPlan string   `gorm:"type:varchar(50);not null"` // e.g., "100", "200"
	StripeAccountID string    `gorm:"type:varchar(255)"`
	MaxSalesLimit   int       `gorm:"not null;default:1000"`
	PrivateJSONData string    `gorm:"type:jsonb"` // Store champion data/rules here
	IsActive        bool      `gorm:"default:true"`
	CreatedAt       time.Time
	UpdatedAt       time.Time
	DeletedAt       gorm.DeletedAt `gorm:"index"`
}

func (g *Group) BeforeCreate(tx *gorm.DB) (err error) {
	if g.ID == uuid.Nil {
		g.ID = uuid.New()
	}
	return
}

type OTPProfile struct {
	ID              uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	OwnerID         uuid.UUID `gorm:"type:uuid;not null;index"`
	ChampionName    string    `gorm:"type:varchar(100);not null"`
	Description     string    `gorm:"type:text"`
	SubscriptionPlan string   `gorm:"type:varchar(50);not null"` // e.g., "10", "20"
	StripeAccountID string    `gorm:"type:varchar(255)"`
	PrivateJSONData string    `gorm:"type:jsonb"` // Store OTP specific rules here
	IsActive        bool      `gorm:"default:true"`
	CreatedAt       time.Time
	UpdatedAt       time.Time
	DeletedAt       gorm.DeletedAt `gorm:"index"`
}

func (o *OTPProfile) BeforeCreate(tx *gorm.DB) (err error) {
	if o.ID == uuid.Nil {
		o.ID = uuid.New()
	}
	return
}
