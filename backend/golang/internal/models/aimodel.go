package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type AIModel struct {
	ID               uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	CreatorID        uuid.UUID `gorm:"type:uuid;not null;index"`
	ChampionName     string    `gorm:"type:varchar(100);not null"`
	EarlyGameStrategy string    `gorm:"type:text"`
	LateGameStrategy  string    `gorm:"type:text"`
	Combos           string    `gorm:"type:text"`
	Synergies        string    `gorm:"type:text"`
	Counters         string    `gorm:"type:text"`
	CoreBuild        string    `gorm:"type:text"`
	SpellsAndRunes   string    `gorm:"type:text"`
	CreatedAt        time.Time
	UpdatedAt        time.Time
}

func (m *AIModel) BeforeCreate(tx *gorm.DB) (err error) {
	if m.ID == uuid.Nil {
		m.ID = uuid.New()
	}
	return
}
