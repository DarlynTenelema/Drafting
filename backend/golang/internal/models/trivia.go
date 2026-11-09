package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type TriviaCategory string

const (
	TriviaCategoryItemCost  TriviaCategory = "item_cost"  // ¿Cuánto cuesta este objeto?
	TriviaCategoryBuildPath TriviaCategory = "build_path" // ¿Qué se está armando?
	TriviaCategoryCounter   TriviaCategory = "counter"    // ¿Cuál es el counter de este campeón?
)

type TriviaQuestion struct {
	ID            uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	Category      TriviaCategory `gorm:"type:varchar(32);index;not null" json:"category"` // item_cost, build_path, counter
	Game          string         `gorm:"type:varchar(32);default:'wild_rift';index" json:"game"` // wild_rift o lol_pc
	QuestionText  string         `gorm:"type:text;not null" json:"question_text"`
	TargetName    string         `gorm:"type:varchar(128);not null" json:"target_name"` // ej: "Fuerza de la Trinidad", "Darius"
	Clues         string         `gorm:"type:text;default:''" json:"clues"`             // pistas / componentes: "Brillo + Furia + Bacteriófago"
	Options       string         `gorm:"type:text;default:'[]'" json:"options"`         // JSON string array: ["A", "B", "C", "D"]
	CorrectAnswer string         `gorm:"type:text;not null" json:"correct_answer"`      // "3333", "Fuerza de la Trinidad", "Vayne"
	Tolerance     int            `gorm:"default:0" json:"tolerance"`                    // Margen de tolerancia para precios numéricos (ej: 0)
	MonthTag      string         `gorm:"type:varchar(32);default:'general';index" json:"month_tag"` // ej: "2026-11"
	Active        bool           `gorm:"default:true;index" json:"active"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
}

func (t *TriviaQuestion) BeforeCreate(tx *gorm.DB) error {
	if t.ID == uuid.Nil {
		t.ID = uuid.New()
	}
	return nil
}

// GetOptions decodifica el campo Options de JSON a slice de strings
func (t *TriviaQuestion) GetOptions() []string {
	var opts []string
	if t.Options == "" || t.Options == "[]" {
		return []string{}
	}
	if err := json.Unmarshal([]byte(t.Options), &opts); err != nil {
		return []string{}
	}
	return opts
}

// SetOptions codifica un slice de strings a JSON en el campo Options
func (t *TriviaQuestion) SetOptions(opts []string) {
	if len(opts) == 0 {
		t.Options = "[]"
		return
	}
	data, err := json.Marshal(opts)
	if err != nil {
		t.Options = "[]"
		return
	}
	t.Options = string(data)
}

// TriviaUserProgress registra el estado de cada pregunta para cada usuario
// para garantizar que las preguntas respondidas correctamente no se repitan
// y solo aparezcan preguntas no vistas o falladas previamente en orden aleatorio.
type TriviaUserProgress struct {
	ID            uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID        uuid.UUID      `gorm:"type:uuid;index;not null" json:"user_id"`
	QuestionID    uuid.UUID      `gorm:"type:uuid;index;not null" json:"question_id"`
	Category      TriviaCategory `gorm:"type:varchar(32);index;not null" json:"category"`
	IsCorrect     bool           `gorm:"default:false;index" json:"is_correct"`
	AttemptsCount int            `gorm:"default:1" json:"attempts_count"`
	LastAttemptAt time.Time      `json:"last_attempt_at"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
}

func (p *TriviaUserProgress) BeforeCreate(tx *gorm.DB) error {
	if p.ID == uuid.Nil {
		p.ID = uuid.New()
	}
	return nil
}

