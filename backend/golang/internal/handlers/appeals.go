package handlers

import (
	"encoding/json"
	"net/http"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
	"github.com/go-chi/chi/v5"
)

// SubmitAppeal allows a pending_ban user to submit an appeal
func SubmitAppeal(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserIDFromContext(r.Context())
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req struct {
		Message string `json:"message"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	db := database.GetDB()

	// Ensure the user actually has a pending ban
	var user models.User
	if err := db.Where("id = ?", userID).First(&user).Error; err != nil || !user.IsPendingBan {
		http.Error(w, "User is not in pending ban state", http.StatusBadRequest)
		return
	}

	appeal := models.Appeal{
		UserID:  userID,
		Message: req.Message,
		Status:  "pending",
	}

	if err := db.Create(&appeal).Error; err != nil {
		http.Error(w, "Failed to submit appeal", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(appeal)
}

// GetAppeals (Admin) gets all appeals
func GetAppeals(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	var appeals []models.Appeal

	status := r.URL.Query().Get("status")
	query := db.Preload("User").Order("created_at desc")
	
	if status != "" {
		query = query.Where("status = ?", status)
	}

	if err := query.Find(&appeals).Error; err != nil {
		http.Error(w, "Failed to fetch appeals", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(appeals)
}

// ResolveAppeal (Admin) accepts or rejects an appeal
func ResolveAppeal(w http.ResponseWriter, r *http.Request) {
	appealID := chi.URLParam(r, "id")
	
	var req struct {
		Status string `json:"status"` // 'approved' (forgiven) or 'rejected' (banned)
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	db := database.GetDB()
	
	tx := db.Begin()

	var appeal models.Appeal
	if err := tx.Where("id = ?", appealID).First(&appeal).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Appeal not found", http.StatusNotFound)
		return
	}

	if err := tx.Model(&appeal).Update("status", req.Status).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to update appeal", http.StatusInternalServerError)
		return
	}

	// Apply user consequences
	var user models.User
	if err := tx.Where("id = ?", appeal.UserID).First(&user).Error; err == nil {
		if req.Status == "approved" {
			// Forgive: remove pending ban, reset strikes to 2 (so they are one strike away from another pending ban)
			tx.Model(&user).Updates(map[string]interface{}{
				"is_pending_ban": false,
				"pending_ban_until": nil,
				"strikes": 2,
			})
		} else if req.Status == "rejected" {
			// Ban permanently
			tx.Model(&user).Updates(map[string]interface{}{
				"is_pending_ban": false,
				"pending_ban_until": nil,
				"banned": true,
			})
		}
	}

	tx.Commit()

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Appeal resolved successfully"})
}
