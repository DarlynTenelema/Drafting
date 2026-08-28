package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// MatchSession represents a collection of screenshots from a single match
type MatchSession struct {
	ID          string            `gorm:"type:uuid;primary_key;" json:"id"`
	UserID      string            `gorm:"type:uuid;not null;index" json:"user_id"`
	Status      string            `gorm:"type:varchar(50);default:'active'" json:"status"` // 'active', 'completed'
	CreatedAt   time.Time         `json:"created_at"`
	UpdatedAt   time.Time         `json:"updated_at"`
	Screenshots []MatchScreenshot `gorm:"foreignKey:MatchSessionID" json:"screenshots"`
	Threads     []MatchChatThread   `gorm:"foreignKey:MatchSessionID" json:"threads"`
}

func (m *MatchSession) BeforeCreate(tx *gorm.DB) (err error) {
	if m.ID == "" {
		m.ID = uuid.New().String()
	}
	return
}

// MatchScreenshot represents an image captured during the match
type MatchScreenshot struct {
	ID             string    `gorm:"type:uuid;primary_key;" json:"id"`
	MatchSessionID string    `gorm:"type:uuid;not null;index" json:"match_session_id"`
	ImageURL       string    `gorm:"not null" json:"image_url"`
	SceneType      string    `gorm:"type:varchar(50)" json:"scene_type"` // 'draft', 'in_game'
	CreatedAt      time.Time `json:"created_at"`
}

func (m *MatchScreenshot) BeforeCreate(tx *gorm.DB) (err error) {
	if m.ID == "" {
		m.ID = uuid.New().String()
	}
	return
}

// MatchChatThread represents a single chat conversation for a match
type MatchChatThread struct {
	ID             string             `gorm:"type:uuid;primary_key;" json:"id"`
	MatchSessionID string             `gorm:"type:uuid;not null;index" json:"match_session_id"`
	Title          string             `gorm:"type:varchar(100);default:'Nuevo Chat'" json:"title"`
	CreatedAt      time.Time          `json:"created_at"`
	UpdatedAt      time.Time          `json:"updated_at"`
	Messages       []MatchChatMessage `gorm:"foreignKey:ThreadID" json:"messages"`
}

func (m *MatchChatThread) BeforeCreate(tx *gorm.DB) (err error) {
	if m.ID == "" {
		m.ID = uuid.New().String()
	}
	return
}

// MatchChatMessage represents a chat message between user and AI regarding a match
type MatchChatMessage struct {
	ID             string    `gorm:"type:uuid;primary_key;" json:"id"`
	ThreadID       string    `gorm:"type:uuid;not null;index" json:"thread_id"`
	Role           string    `gorm:"type:varchar(50);not null" json:"role"` // 'user', 'model'
	Content        string    `gorm:"type:text;not null" json:"content"`
	CreatedAt      time.Time `json:"created_at"`
}

func (m *MatchChatMessage) BeforeCreate(tx *gorm.DB) (err error) {
	if m.ID == "" {
		m.ID = uuid.New().String()
	}
	return
}
