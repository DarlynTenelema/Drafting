package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"backend/internal/database"
	"backend/internal/models"
	"github.com/go-chi/chi/v5"
)

// SearchUsers returns a list of users based on search criteria
func SearchUsers(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	var users []models.User

	queryStr := r.URL.Query().Get("q")

	query := db.Order("created_at desc").Limit(50) // Limitar resultados por rendimiento

	if queryStr != "" {
		query = query.Where("email ILIKE ?", "%"+queryStr+"%")
	}

	if err := query.Find(&users).Error; err != nil {
		http.Error(w, "Failed to fetch users", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(users)
}

// GetUserDetail returns detailed information about a specific user
func GetUserDetail(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	
	db := database.GetDB()
	var user models.User

	if err := db.Where("id = ?", userID).First(&user).Error; err != nil {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}

	// Fetch related content to show in the "God Mode" dashboard
	var videos []models.VideoEmbed
	var fanarts []models.Fanart
	
	// Fetching channels where user is owner to get videos
	var channel models.Channel
	db.Where("owner_id = ?", userID).First(&channel)
	
	if channel.ID.String() != "00000000-0000-0000-0000-000000000000" {
		db.Where("channel_id = ?", channel.ID).Find(&videos)
	}

	db.Where("creator_id = ?", userID).Find(&fanarts)

	response := map[string]interface{}{
		"user":    user,
		"channel": channel,
		"videos":  videos,
		"fanarts": fanarts,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// ToggleBan suspends or unsuspends a user
func ToggleBan(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	
	var req struct {
		Banned bool `json:"banned"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	db := database.GetDB()
	if err := db.Model(&models.User{}).Where("id = ?", userID).Update("banned", req.Banned).Error; err != nil {
		http.Error(w, "Failed to update user ban status", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "User ban status updated successfully"})
}

// AddStrike increments the user's strike count
func AddStrike(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")

	db := database.GetDB()
	
	var user models.User
	if err := db.Where("id = ?", userID).First(&user).Error; err != nil {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}

	newStrikes := user.Strikes + 1
	updates := map[string]interface{}{
		"strikes": newStrikes,
	}

	// Si llega a 5 strikes, es ban permanente. Si llega a 3 o 4, es ban temporal (pending ban).
	if newStrikes >= 5 {
		updates["banned"] = true
		updates["is_pending_ban"] = false
	} else if newStrikes >= 3 {
		updates["is_pending_ban"] = true
		banDate := time.Now().Add(7 * 24 * time.Hour)
		updates["pending_ban_until"] = &banDate
	}

	if err := db.Model(&user).Updates(updates).Error; err != nil {
		http.Error(w, "Failed to update user", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":        "Strike added successfully",
		"strikes":        newStrikes,
		"is_pending_ban": newStrikes >= 3,
	})
}
