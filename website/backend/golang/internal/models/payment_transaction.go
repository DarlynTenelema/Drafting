package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type PaymentTransaction struct {
	ID            uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	UserID        uuid.UUID `gorm:"type:uuid;not null;index"`
	PlanID        string    `gorm:"type:varchar(50);not null"`
	ProductID     string    `gorm:"type:varchar(100);not null"`
	PurchaseToken string    `gorm:"type:varchar(512);uniqueIndex;not null"`
	Amount        float64   `gorm:"type:decimal(10,2);not null"`
	Status        string    `gorm:"type:varchar(50);not null;default:pending"`
	CreatedAt     time.Time
	UpdatedAt     time.Time
}

func (tx *PaymentTransaction) BeforeCreate(db *gorm.DB) error {
	if tx.ID == uuid.Nil {
		tx.ID = uuid.New()
	}
	return nil
}
