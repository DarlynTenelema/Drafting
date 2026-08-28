package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type SuspiciousTransaction struct {
	ID              uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID          uuid.UUID `gorm:"type:uuid;not null" json:"user_id"`
	TransactionID   *string   `gorm:"type:varchar(255)" json:"transaction_id"`
	Amount          float64   `gorm:"type:decimal(10,2);not null" json:"amount"`
	TransactionType string    `gorm:"type:varchar(50);not null" json:"transaction_type"` // 'chargeback', 'mass_withdrawal', 'suspicious_payment'
	Status          string    `gorm:"type:varchar(50);default:'pending'" json:"status"` // 'pending', 'resolved_refunded', 'resolved_banned', 'ignored'
	Reason          string    `gorm:"type:text;not null" json:"reason"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`

	// Relación
	User *User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

func (st *SuspiciousTransaction) BeforeCreate(tx *gorm.DB) (err error) {
	if st.ID == uuid.Nil {
		st.ID = uuid.New()
	}
	return
}
