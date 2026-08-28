package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Suggestion struct {
	ID          uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID      uuid.UUID `gorm:"type:uuid;not null" json:"user_id"`
	Category    string    `gorm:"type:varchar(50);default:'other'" json:"category"`
	Title       string    `gorm:"type:varchar(255);not null" json:"title"`
	Description string    `gorm:"type:text;not null" json:"description"`
	Status      string    `gorm:"type:varchar(50);default:'new'" json:"status"`
	Upvotes     int       `gorm:"default:0" json:"upvotes"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`

	// Relación
	User *User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

func (s *Suggestion) BeforeCreate(tx *gorm.DB) (err error) {
	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	return
}
