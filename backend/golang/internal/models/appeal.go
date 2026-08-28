package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Appeal struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID    uuid.UUID `gorm:"type:uuid;not null" json:"user_id"`
	Message   string    `gorm:"type:text;not null" json:"message"`
	Status    string    `gorm:"type:varchar(50);default:'pending'" json:"status"` // pending, approved, rejected
	CreatedAt time.Time `json:"created_at"`

	User *User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

func (a *Appeal) BeforeCreate(tx *gorm.DB) (err error) {
	if a.ID == uuid.Nil {
		a.ID = uuid.New()
	}
	return
}
