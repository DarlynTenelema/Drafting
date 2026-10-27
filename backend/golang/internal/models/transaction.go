package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Transaction struct {
	ID                     uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID                 uuid.UUID      `gorm:"type:uuid;index;not null" json:"user_id"`
	Type                   string         `gorm:"type:varchar(50);not null" json:"type"` // "pack" | "subscription"
	ItemKey                string         `gorm:"type:varchar(50);not null" json:"item_key"` // "starter", "plus", "pro", "ultra"
	AmountUSD              float64        `gorm:"type:decimal(10,2);not null" json:"amount_usd"`
	QueriesAdded           int            `gorm:"not null" json:"queries_added"`
	Provider               string         `gorm:"type:varchar(50);default:'google_play'" json:"provider"`
	ProviderTransactionID string         `gorm:"type:varchar(255)" json:"provider_transaction_id"`
	Status                 string         `gorm:"type:varchar(50);default:'completed'" json:"status"`
	CreatedAt              time.Time      `json:"created_at"`
	DeletedAt              gorm.DeletedAt `gorm:"index" json:"-"`
}

func (t *Transaction) BeforeCreate(tx *gorm.DB) (err error) {
	if t.ID == uuid.Nil {
		t.ID = uuid.New()
	}
	return
}
