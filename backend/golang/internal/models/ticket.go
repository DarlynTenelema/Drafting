package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Ticket struct {
	ID               uuid.UUID  `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID           uuid.UUID  `gorm:"type:uuid;not null" json:"user_id"`
	Subject          string     `gorm:"type:varchar(255);not null" json:"subject"`
	TicketType       string     `gorm:"type:varchar(50);not null" json:"ticket_type"` // 'bug', 'fraud', 'support', 'other'
	Status           string     `gorm:"type:varchar(50);default:'open'" json:"status"` // 'open', 'in_progress', 'resolved', 'closed'
	Priority         string     `gorm:"type:varchar(50);default:'medium'" json:"priority"`
	AssignedAdminID  *uuid.UUID `gorm:"type:uuid" json:"assigned_admin_id"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`

	// Relaciones (Opcional, para preloads)
	User         *User           `gorm:"foreignKey:UserID" json:"user,omitempty"`
	AssignedAdmin *User          `gorm:"foreignKey:AssignedAdminID" json:"assigned_admin,omitempty"`
}

func (t *Ticket) BeforeCreate(tx *gorm.DB) (err error) {
	if t.ID == uuid.Nil {
		t.ID = uuid.New()
	}
	return
}

type TicketMessage struct {
	ID             uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	TicketID       uuid.UUID `gorm:"type:uuid;not null" json:"ticket_id"`
	SenderID       uuid.UUID `gorm:"type:uuid;not null" json:"sender_id"`
	Message        string    `gorm:"type:text;not null" json:"message"`
	EvidenceURL    string    `gorm:"type:varchar(512)" json:"evidence_url,omitempty"`
	IsInternalNote bool      `gorm:"default:false" json:"is_internal_note"`
	CreatedAt      time.Time `json:"created_at"`

	// Relaciones
	Sender *User `gorm:"foreignKey:SenderID" json:"sender,omitempty"`
}

func (tm *TicketMessage) BeforeCreate(tx *gorm.DB) (err error) {
	if tm.ID == uuid.Nil {
		tm.ID = uuid.New()
	}
	return
}
