package models

import (
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type User struct {
	ID                     uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	GoogleID               *string        `gorm:"type:varchar(255);unique"`
	Email                  string         `gorm:"type:varchar(255);not null"`
	Username               string         `gorm:"type:varchar(255)"`
	ProfilePic             string         `gorm:"type:varchar(255)"`
	PasswordHash           string         `gorm:"type:varchar(255)"`
	DeviceID               string         `gorm:"type:varchar(255)"`
	SessionToken           string         `gorm:"type:varchar(255)"`
	Role                   string         `gorm:"type:varchar(50);default:'consumer'"`
	Banned                 bool           `gorm:"default:false"`
	ActivePlan             *string        `gorm:"type:varchar(50);default:'freemium'"` // 'freemium', 'plus', 'pro'
	AvailableQueries       int            `gorm:"default:13"`
	BonusQueries           int            `gorm:"default:10"` // Consultas por ser nuevo (máximo 10)
	DailyQueries           int            `gorm:"default:3"`  // Consultas diarias (tope máximo de 3)
	AdQueries              int            `gorm:"default:0"`  // Consultas por recarga / anuncios
	LastDailyRewardDate    string         `gorm:"type:varchar(10);default:''"`
	ReferralCode           string         `gorm:"type:varchar(16);index"`
	ReferredByID           *uuid.UUID     `gorm:"type:uuid;index"`
	ReferralCount          int            `gorm:"default:0"`
	ReferralRewardsClaimed int            `gorm:"default:0"`
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

// ConsumeQuery descuenta 1 consulta priorizando: 1) Diarias, 2) Bono de bienvenida, 3) Recargas por anuncios
func (user *User) ConsumeQuery() bool {
	if user.AvailableQueries <= 0 {
		return false
	}
	if user.DailyQueries > 0 {
		user.DailyQueries--
	} else if user.BonusQueries > 0 {
		user.BonusQueries--
	} else if user.AdQueries > 0 {
		user.AdQueries--
	}
	user.AvailableQueries = user.DailyQueries + user.BonusQueries + user.AdQueries
	if user.AvailableQueries < 0 {
		user.AvailableQueries = 0
	}
	return true
}

// AddAdQueries suma consultas por ver anuncios o logros de referidos (crece infinitamente sin tope)
func (user *User) AddAdQueries(amount int) {
	user.AdQueries += amount
	user.AvailableQueries = user.DailyQueries + user.BonusQueries + user.AdQueries
}

// RefreshDailyQueries restablece las consultas diarias a 3 (máximo 3, NUNCA acumula más allá de 3)
func (user *User) RefreshDailyQueries(today string) bool {
	if user.LastDailyRewardDate != today {
		user.DailyQueries = 3 // Tope estricto de 3
		user.LastDailyRewardDate = today
		user.AvailableQueries = user.DailyQueries + user.BonusQueries + user.AdQueries
		return true
	}
	return false
}

func (user *User) BeforeCreate(tx *gorm.DB) (err error) {
	if user.ID == uuid.Nil {
		user.ID = uuid.New()
	}
	if user.BonusQueries == 0 && user.AvailableQueries == 0 {
		user.BonusQueries = 10
		user.DailyQueries = 3
		user.AdQueries = 0
		user.AvailableQueries = 13
		user.LastDailyRewardDate = time.Now().UTC().Format("2006-01-02")
	} else if user.AvailableQueries == 0 {
		user.AvailableQueries = user.DailyQueries + user.BonusQueries + user.AdQueries
	}
	if user.ReferralCode == "" {
		user.ReferralCode = GenerateReferralCode(user.ID)
	}
	return
}

