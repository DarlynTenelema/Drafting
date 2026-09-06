package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type AIModel struct {
	ID                uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	CreatorID         uuid.UUID `gorm:"type:uuid;not null;index" json:"creator_id"`
	ChampionName      string    `gorm:"type:varchar(100);not null" json:"champion_name"`
	EarlyGameStrategy string    `gorm:"type:text" json:"early_game_strategy"`
	LateGameStrategy  string    `gorm:"type:text" json:"late_game_strategy"`
	Combos            string    `gorm:"type:text" json:"combos"`
	Synergies         string    `gorm:"type:text" json:"synergies"`
	Counters          string    `gorm:"type:text" json:"counters"`
	CoreBuild         string    `gorm:"type:text" json:"core_build"`
	SpellsAndRunes    string    `gorm:"type:text" json:"spells_and_runes"`
	SituationalItems  string    `gorm:"type:text" json:"situational_items"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

func (m *AIModel) BeforeCreate(tx *gorm.DB) (err error) {
	if m.ID == uuid.Nil {
		m.ID = uuid.New()
	}
	return
}
