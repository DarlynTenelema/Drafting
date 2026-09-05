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
	ProductName     string    `gorm:"type:varchar(255)"`
	ProductImage    string    `gorm:"type:varchar(500)"`
	MaxSalesLimit   int       `gorm:"not null;default:1000"`
	PrivateJSONData string    `gorm:"type:jsonb"` // Store champion data/rules here
	IsActive        bool      `gorm:"default:true"`
	PurchaseToken   string    `gorm:"type:varchar(512);uniqueIndex"` // Used to track Google Play subscription
	DeletionScheduledFor *time.Time `gorm:"type:timestamp with time zone;default:null"`
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
	ProductName     string    `gorm:"type:varchar(255)"`
	ProductImage    string    `gorm:"type:varchar(500)"`
	PrivateJSONData string    `gorm:"type:jsonb"` // Store OTP specific rules here
	IsActive        bool      `gorm:"default:true"`
	PurchaseToken   string    `gorm:"type:varchar(512);uniqueIndex"` // Used to track Google Play subscription
	DeletionScheduledFor *time.Time `gorm:"type:timestamp with time zone;default:null"`
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

type GroupInvitation struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	GroupID   uuid.UUID `gorm:"type:uuid;not null;index"`
	Email     string    `gorm:"type:varchar(255);not null"`
	Status    string    `gorm:"type:varchar(50);default:'pending'"` // pending, accepted
	CreatedAt time.Time
	UpdatedAt time.Time
}

func (g *GroupInvitation) BeforeCreate(tx *gorm.DB) (err error) {
	if g.ID == uuid.Nil {
		g.ID = uuid.New()
	}
	return
}

