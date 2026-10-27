package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type QueryTransfer struct {
	ID               uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	FromUserID       uuid.UUID      `gorm:"type:uuid;index;not null" json:"from_user_id"`
	FromReferralCode string         `gorm:"type:varchar(16)" json:"from_referral_code"`
	ToUserID         uuid.UUID      `gorm:"type:uuid;index;not null" json:"to_user_id"`
	ToReferralCode   string         `gorm:"type:varchar(16)" json:"to_referral_code"`
	Amount           int            `gorm:"not null" json:"amount"`
	CreatedAt        time.Time      `json:"created_at"`
	DeletedAt        gorm.DeletedAt `gorm:"index" json:"-"`
}

func (q *QueryTransfer) BeforeCreate(tx *gorm.DB) (err error) {
	if q.ID == uuid.Nil {
		q.ID = uuid.New()
	}
	return
}
