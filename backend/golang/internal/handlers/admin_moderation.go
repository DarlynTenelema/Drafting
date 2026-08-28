package handlers

import (
	"encoding/json"
	"net/http"

	"backend/internal/database"
	"backend/internal/models"
	"github.com/go-chi/chi/v5"
)

// GetPendingContent returns all content (videos and fanarts) awaiting moderation
func GetPendingContent(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	
	var videos []models.VideoEmbed
	var fanarts []models.Fanart

	db.Where("status = ?", "pending").Find(&videos)
	db.Where("status = ?", "pending").Find(&fanarts)

	response := map[string]interface{}{
		"videos":  videos,
		"fanarts": fanarts,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// ModerateVideo approves or rejects a video
func ModerateVideo(w http.ResponseWriter, r *http.Request) {
	videoID := chi.URLParam(r, "id")
	
	var req struct {
		Action string `json:"action"` // 'approve' or 'reject'
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	db := database.GetDB()
	newStatus := "rejected"
	if req.Action == "approve" {
		newStatus = "approved"
	}

	if err := db.Model(&models.VideoEmbed{}).Where("id = ?", videoID).Update("status", newStatus).Error; err != nil {
		http.Error(w, "Failed to moderate video", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Video moderated successfully"})
}

// ModerateFanart approves or rejects a fanart
func ModerateFanart(w http.ResponseWriter, r *http.Request) {
	fanartID := chi.URLParam(r, "id")
	
	var req struct {
		Action string `json:"action"` // 'approve' or 'reject'
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	db := database.GetDB()
	newStatus := "rejected"
	if req.Action == "approve" {
		newStatus = "approved"
	}

	if err := db.Model(&models.Fanart{}).Where("id = ?", fanartID).Update("status", newStatus).Error; err != nil {
		http.Error(w, "Failed to moderate fanart", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Fanart moderated successfully"})
}
