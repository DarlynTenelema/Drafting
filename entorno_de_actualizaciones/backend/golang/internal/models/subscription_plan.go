package models

import "time"

type SubscriptionPlan struct {
	ID            string    `gorm:"type:varchar(50);primaryKey"`
	Price         float64   `gorm:"type:decimal(10,2);not null"`
	DurationHours int       `gorm:"not null"`
	CreatedAt     time.Time
}
