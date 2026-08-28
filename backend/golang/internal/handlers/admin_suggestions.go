package handlers

import (
	"encoding/json"
	"net/http"

	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/models"
	"github.com/go-chi/chi/v5"
)

// GetSuggestions returns a list of user suggestions
func GetSuggestions(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	var suggestions []models.Suggestion

	status := r.URL.Query().Get("status")
	category := r.URL.Query().Get("category")

	query := db.Preload("User").Order("created_at desc")
	
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if category != "" {
		query = query.Where("category = ?", category)
	}

	if err := query.Find(&suggestions).Error; err != nil {
		http.Error(w, "Failed to fetch suggestions", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(suggestions)
}

// UpdateSuggestionStatus changes the status of a suggestion
func UpdateSuggestionStatus(w http.ResponseWriter, r *http.Request) {
	suggestionID := chi.URLParam(r, "id")
	
	var req struct {
		Status string `json:"status"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	db := database.GetDB()
	
	if err := db.Model(&models.Suggestion{}).Where("id = ?", suggestionID).Update("status", req.Status).Error; err != nil {
		http.Error(w, "Failed to update suggestion", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Suggestion updated successfully"})
}

// GroupSuggestionsWithAI uses Gemini to cluster suggestions
func GroupSuggestionsWithAI(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	var suggestions []models.Suggestion

	// Only group "pending" suggestions, for example status 'new' or 'open'
	// Since we don't know the exact schema, let's just fetch all or where status='open'
	if err := db.Find(&suggestions).Error; err != nil {
		http.Error(w, "Failed to fetch suggestions", http.StatusInternalServerError)
		return
	}

	if len(suggestions) == 0 {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte("[]"))
		return
	}

	// Prepare simple JSON array for the AI
	type AiInput struct {
		ID          string `json:"id"`
		Title       string `json:"title"`
		Description string `json:"description"`
	}
	var inputList []AiInput
	for _, s := range suggestions {
		inputList = append(inputList, AiInput{
			ID:          s.ID.String(),
			Title:       s.Title,
			Description: s.Description,
		})
	}

	inputBytes, _ := json.Marshal(inputList)

	responseStr, err := gemini.GroupSuggestions(r.Context(), string(inputBytes))
	if err != nil {
		http.Error(w, "Error communicating with AI: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// AI returns a JSON array string. We can just pipe it directly back to the client!
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(responseStr))
}

