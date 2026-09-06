package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"

	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/middleware"
	"backend/internal/models"
)

type SaveAIModelRequest struct {
	ChampionName      string `json:"champion_name"`
	EarlyGameStrategy string `json:"early_game_strategy"`
	LateGameStrategy  string `json:"late_game_strategy"`
	Combos            string `json:"combos"`
	Synergies         string `json:"synergies"`
	Counters          string `json:"counters"`
	CoreBuild         string `json:"core_build"`
	SpellsAndRunes    string `json:"spells_and_runes"`
}

func SaveAIModel(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	if user.Banned {
		http.Error(w, "Cuenta suspendida permanentemente por múltiples infracciones", http.StatusForbidden)
		return
	}

	var req SaveAIModelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Cuerpo de solicitud inválido", http.StatusBadRequest)
		return
	}

	reqJSON, _ := json.Marshal(req)
	
	// Moderate Text using Gemini 2.5 Flash
	approved, reason, err := gemini.ModerateText(r.Context(), string(reqJSON))
	if err != nil {
		http.Error(w, "Error al moderar el contenido", http.StatusInternalServerError)
		return
	}

	if !approved {
		user.Strikes++
		
		if user.Strikes >= 5 {
			user.Banned = true
		}
		
		database.DB.Save(user)

		msg := fmt.Sprintf("Contenido rechazado. Razón: %s. Strike %d/5.", reason, user.Strikes)
		if user.Banned {
			msg = "Cuenta suspendida permanentemente por acumular 5 strikes."
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error":   true,
			"message": msg,
			"strikes": user.Strikes,
			"banned":  user.Banned,
		})
		return
	}

	// Content is approved, save it.
	aiModel := models.AIModel{
		CreatorID:         user.ID,
		ChampionName:      req.ChampionName,
		EarlyGameStrategy: req.EarlyGameStrategy,
		LateGameStrategy:  req.LateGameStrategy,
		Combos:            req.Combos,
		Synergies:         req.Synergies,
		Counters:          req.Counters,
		CoreBuild:         req.CoreBuild,
		SpellsAndRunes:    req.SpellsAndRunes,
	}

	// Upsert based on CreatorID and ChampionName if you want one per champ, 
	// or just create new if you keep history. For now, we create or update.
	var existing models.AIModel
	if err := database.DB.Where("creator_id = ? AND champion_name = ?", user.ID, req.ChampionName).First(&existing).Error; err == nil {
		// Update existing
		existing.EarlyGameStrategy = req.EarlyGameStrategy
		existing.LateGameStrategy = req.LateGameStrategy
		existing.Combos = req.Combos
		existing.Synergies = req.Synergies
		existing.Counters = req.Counters
		existing.CoreBuild = req.CoreBuild
		existing.SpellsAndRunes = req.SpellsAndRunes
		database.DB.Save(&existing)
	} else {
		// Create new
		database.DB.Create(&aiModel)
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Modelo IA guardado y entrenado exitosamente",
	})
}

// GetAllAIModels returns all models created by this user
func GetAllAIModels(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var aiModels []models.AIModel
	if err := database.DB.Where("creator_id = ?", user.ID).Find(&aiModels).Error; err != nil {
		http.Error(w, "Error fetching models", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(aiModels)
}

// UpdateAIModel updates an existing AI model
func UpdateAIModel(w http.ResponseWriter, r *http.Request) {
	// Re-uses SaveAIModel logic for now since it does an Upsert
	SaveAIModel(w, r)
}

// DeleteAIModel deletes an AI model for the user
func DeleteAIModel(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req struct {
		ChampionName string `json:"champion_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if err := database.DB.Where("creator_id = ? AND champion_name = ?", user.ID, req.ChampionName).Delete(&models.AIModel{}).Error; err != nil {
		http.Error(w, "Error deleting model", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
	})
}
