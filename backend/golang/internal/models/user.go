package models

import (
	"strings"
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
	HasUsedCreatorTrial bool `gorm:"default:false"`
	ActiveGroupID *uuid.UUID `gorm:"type:uuid"` // The group the user is subscribed to
	CurrentGoal   *string    `gorm:"type:varchar(255)"` // The current short-term goal for the AI coach
	ActivePlan    *string    `gorm:"type:varchar(50);default:'freemium'"` // e.g., 'freemium', 'plus', 'pro', 'ultra'
	AvailableQueries       int        `gorm:"default:10"`
	LastDailyRewardDate    string     `gorm:"type:varchar(10);default:''"`
	ReferralCode           string     `gorm:"type:varchar(16);uniqueIndex"`
	ReferredByID           *uuid.UUID `gorm:"type:uuid;index"`
	ReferralCount          int        `gorm:"default:0"`
	ReferralRewardsClaimed int        `gorm:"default:0"`
	TokensUsedInCycle      int        `gorm:"default:0"`
	LastTokenResetDate     *time.Time `gorm:""`
	LastDraftAt            time.Time
	SubscriptionEndsAt     *time.Time
	CreatedAt              time.Time
	UpdatedAt              time.Time
	DeletedAt              gorm.DeletedAt `gorm:"index"`
}

func GenerateReferralCode(id uuid.UUID) string {
	clean := strings.ToUpper(strings.ReplaceAll(id.String(), "-", ""))
	if len(clean) >= 6 {
		return "WR" + clean[:6]
	}
	return "WR" + clean
}

func (user *User) BeforeCreate(tx *gorm.DB) (err error) {
	if user.ID == uuid.Nil {
		user.ID = uuid.New()
	}
	if user.AvailableQueries == 0 {
		user.AvailableQueries = 10
	}
	if user.ReferralCode == "" {
		user.ReferralCode = GenerateReferralCode(user.ID)
	}
	return
}

