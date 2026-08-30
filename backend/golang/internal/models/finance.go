package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)


type Wallet struct {
	ID          uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	UserID      uuid.UUID `gorm:"type:uuid;unique;not null"`
	BalanceUSD     float64   `gorm:"type:decimal(10,2);default:0.00"` // For creators earning money
	BalanceEssence float64   `gorm:"type:decimal(10,2);default:0.00"` // Blue Essences for consumers
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

func (w *Wallet) BeforeCreate(tx *gorm.DB) (err error) {
	if w.ID == uuid.Nil {
		w.ID = uuid.New()
	}
	return
}

type Transaction struct {
	ID              uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	UserID          uuid.UUID `gorm:"type:uuid;not null;index"`
	Type            string    `gorm:"type:varchar(50);not null"` // "recharge_essence", "purchase_fanart", "api_deduction", "payout"
	AmountUSD       float64   `gorm:"type:decimal(10,2);default:0.00"`
	AmountEssence   float64   `gorm:"type:decimal(10,2);default:0.00"`
	RelatedEntityID *uuid.UUID `gorm:"type:uuid"` // E.g., FanartID, or APIUsageID
	Status          string    `gorm:"type:text;default:'completed'"`
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

func (t *Transaction) BeforeCreate(tx *gorm.DB) (err error) {
	if t.ID == uuid.Nil {
		t.ID = uuid.New()
	}
	return
}
