package models

import (
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type User struct {
	ID                     uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	GoogleID               *string        `gorm:"type:varchar(255);unique" json:"google_id,omitempty"`
	Email                  string         `gorm:"type:varchar(255);not null" json:"email"`
	Username               string         `gorm:"type:varchar(255)" json:"username"`
	ProfilePic             string         `gorm:"type:varchar(255)" json:"profile_pic"`
	PasswordHash           string         `gorm:"type:varchar(255)" json:"-"`
	DeviceID               string         `gorm:"type:varchar(255)" json:"device_id,omitempty"`
	SessionToken           string         `gorm:"type:varchar(255)" json:"-"`
	Role                   string         `gorm:"type:varchar(50);default:'consumer'" json:"role"`
	Banned                 bool           `gorm:"default:false" json:"banned"`
	ActivePlan             *string        `gorm:"type:varchar(50);default:'freemium'" json:"active_plan"` // 'freemium', 'plus', 'pro'

	// Consultas disponibles y sus fuentes
	AvailableQueries       int            `gorm:"default:8" json:"available_queries"`
	BonusQueries           int            `gorm:"default:5" json:"bonus_queries"`           // Consultas por ser nuevo (5)
	DailyQueries           int            `gorm:"default:3" json:"daily_queries"`             // Consultas diarias (tope máximo de 3)
	AdQueries              int            `gorm:"default:0" json:"ad_queries"`               // Consultas por recarga de anuncios / recompensas
	PurchasedQueries       int            `gorm:"default:0" json:"purchased_queries"`        // Consultas compradas en paquetes (permanentes)
	SubscriptionQueries    int            `gorm:"default:0" json:"subscription_queries"`     // Consultas del mes por suscripción activa
	GiftQueries            int            `gorm:"default:0" json:"gift_queries"`             // Consultas exclusivas para regalar a amigos (ej. 25 del Pack Starter)

	// Suscripción mensual
	SubscriptionPlan       string         `gorm:"type:varchar(50);default:'none'" json:"subscription_plan"` // 'none', 'plus', 'pro', 'ultra'
	SubscriptionEndsAt     *time.Time     `json:"subscription_ends_at"`
	HasPurchasedStarter    bool           `gorm:"default:false" json:"has_purchased_starter"` // True tras comprar Pack Starter $0.19 (desaparece)

	// Sistema de compartir consultas (Máximo 10 por día para suscriptores)
	DailyTransferredToday  int            `gorm:"default:0" json:"daily_transferred_today"`
	LastTransferDate       string         `gorm:"type:varchar(10);default:''" json:"last_transfer_date"`
	DailyReceivedToday     int            `gorm:"default:0" json:"daily_received_today"`
	LastReceivedDate       string         `gorm:"type:varchar(10);default:''" json:"last_received_date"`

	LastDailyRewardDate    string         `gorm:"type:varchar(10);default:''" json:"last_daily_reward_date"`
	ReferralCode           string         `gorm:"type:varchar(16);index" json:"referral_code"`
	ReferredByID           *uuid.UUID     `gorm:"type:uuid;index" json:"referred_by_id,omitempty"`
	ReferralCount          int            `gorm:"default:0" json:"referral_count"`
	ReferralRewardsClaimed int            `gorm:"default:0" json:"referral_rewards_claimed"`
	LastDraftAt            time.Time      `json:"last_draft_at"`
	CreatedAt              time.Time      `json:"created_at"`
	UpdatedAt              time.Time      `json:"updated_at"`
	DeletedAt              gorm.DeletedAt `gorm:"index" json:"-"`
}

func GenerateReferralCode(id uuid.UUID) string {
	clean := strings.ToUpper(strings.ReplaceAll(id.String(), "-", ""))
	if len(clean) >= 6 {
		return "WR" + clean[:6]
	}
	return "WR" + clean
}

// CheckSubscriptionExpiry verifica y actualiza el plan si ya venció el ciclo de suscripción
func (user *User) CheckSubscriptionExpiry() bool {
	if user.SubscriptionEndsAt != nil && time.Now().After(*user.SubscriptionEndsAt) {
		user.SubscriptionPlan = "none"
		// Las consultas no caducan al acabar el mes; se conservan y acumulan
		user.SubscriptionEndsAt = nil
		user.RecalculateAvailableQueries()
		return true
	}
	return false
}

// IsSubscribed indica si el usuario tiene una suscripción activa vigente
func (user *User) IsSubscribed() bool {
	user.CheckSubscriptionExpiry()
	return user.SubscriptionPlan != "" && user.SubscriptionPlan != "none" && user.SubscriptionEndsAt != nil && time.Now().Before(*user.SubscriptionEndsAt)
}

// CanTransfer indica si el usuario tiene permisos para compartir consultas con amigos
// (Todos los paquetes comprados, usuarios con Pack Starter o suscriptores pueden compartir)
func (user *User) CanTransfer() bool {
	return user.IsSubscribed() || user.HasPurchasedStarter || user.PurchasedQueries > 0 || user.GiftQueries > 0
}

// RecalculateAvailableQueries actualiza la suma total de consultas disponibles
func (user *User) RecalculateAvailableQueries() {
	user.AvailableQueries = user.DailyQueries + user.BonusQueries + user.AdQueries + user.PurchasedQueries + user.SubscriptionQueries
	if user.AvailableQueries < 0 {
		user.AvailableQueries = 0
	}
}

// ConsumeQuery descuenta 1 consulta con el orden de prioridad más conveniente para el usuario:
// 1) Diarias (vencen hoy si no se usan)
// 2) Suscripción (se renuevan/vencen mensualmente)
// 3) Bono de bienvenida
// 4) Recargas por anuncios / referidos
// 5) Consultas compradas en paquetes (permanentes, se guardan al final)
func (user *User) ConsumeQuery() bool {
	user.CheckSubscriptionExpiry()
	user.RecalculateAvailableQueries()
	if user.AvailableQueries <= 0 {
		return false
	}
	if user.DailyQueries > 0 {
		user.DailyQueries--
	} else if user.SubscriptionQueries > 0 {
		user.SubscriptionQueries--
	} else if user.BonusQueries > 0 {
		user.BonusQueries--
	} else if user.AdQueries > 0 {
		user.AdQueries--
	} else if user.PurchasedQueries > 0 {
		user.PurchasedQueries--
	}
	user.RecalculateAvailableQueries()
	return true
}

// DeductTransferQueries descuenta consultas para compartir con un amigo,
// priorizando las GiftQueries (exclusivas de regalo), luego Suscripción, Compradas, Anuncios, Bono y Diarias.
func (user *User) DeductTransferQueries(amount int) bool {
	if amount <= 0 {
		return false
	}
	user.CheckSubscriptionExpiry()
	user.RecalculateAvailableQueries()
	if user.GiftQueries+user.AvailableQueries < amount {
		return false
	}

	remaining := amount
	buckets := []*int{
		&user.GiftQueries,
		&user.SubscriptionQueries,
		&user.PurchasedQueries,
		&user.AdQueries,
		&user.BonusQueries,
		&user.DailyQueries,
	}

	for _, bucket := range buckets {
		if remaining <= 0 {
			break
		}
		if *bucket > 0 {
			if *bucket >= remaining {
				*bucket -= remaining
				remaining = 0
			} else {
				remaining -= *bucket
				*bucket = 0
			}
		}
	}

	user.RecalculateAvailableQueries()
	return remaining == 0
}

// AddAdQueries suma consultas por ver anuncios o logros de referidos
func (user *User) AddAdQueries(amount int) {
	user.AdQueries += amount
	user.RecalculateAvailableQueries()
}

// AddPurchasedQueries agrega consultas compradas de forma permanente
func (user *User) AddPurchasedQueries(amount int) {
	user.PurchasedQueries += amount
	user.RecalculateAvailableQueries()
}

// RefreshDailyQueries restablece las consultas diarias a 3 (máximo 3, NUNCA acumula más allá de 3)
func (user *User) RefreshDailyQueries(today string) bool {
	user.CheckSubscriptionExpiry()
	if user.LastDailyRewardDate != today {
		user.DailyQueries = 3 // Tope estricto de 3
		user.LastDailyRewardDate = today
		user.RecalculateAvailableQueries()
		return true
	}
	return false
}

// ResetDailyLimitsIfNewDay reinicia los contadores diarios de transferencias recibidas y enviadas
func (user *User) ResetDailyLimitsIfNewDay(today string) {
	if user.LastTransferDate != today {
		user.DailyTransferredToday = 0
		user.LastTransferDate = today
	}
	if user.LastReceivedDate != today {
		user.DailyReceivedToday = 0
		user.LastReceivedDate = today
	}
}

func (user *User) BeforeCreate(tx *gorm.DB) (err error) {
	if user.ID == uuid.Nil {
		user.ID = uuid.New()
	}
	if user.BonusQueries == 0 && user.AvailableQueries == 0 {
		user.BonusQueries = 5
		user.DailyQueries = 3
		user.AdQueries = 0
		user.PurchasedQueries = 0
		user.SubscriptionQueries = 0
		user.SubscriptionPlan = "none"
		user.AvailableQueries = 8
		user.LastDailyRewardDate = time.Now().UTC().Format("2006-01-02")
	} else if user.AvailableQueries == 0 {
		user.RecalculateAvailableQueries()
	}
	if user.ReferralCode == "" {
		user.ReferralCode = GenerateReferralCode(user.ID)
	}
	return
}
