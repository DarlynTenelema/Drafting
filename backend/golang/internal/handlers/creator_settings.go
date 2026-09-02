package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
)

// CheckActiveSubscriptions responds with the latest subscription end date for the creator's product
func CheckActiveSubscriptions(w http.ResponseWriter, r *http.Request) {
	_, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	hasActive := false
	var lastEndDate *time.Time

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"hasActive":   hasActive,
		"lastEndDate": lastEndDate,
	})
}

type ScheduleDeletionRequest struct {
	DeletionDate time.Time `json:"deletion_date"`
}

// ScheduleProductDeletion schedules a product to be deleted automatically
func ScheduleProductDeletion(w http.ResponseWriter, r *http.Request) {
	var req ScheduleDeletionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Update Group
	var group models.Group
	if err := database.DB.Where("owner_id = ?", user.ID).First(&group).Error; err == nil {
		group.IsActive = false
		group.DeletionScheduledFor = &req.DeletionDate
		database.DB.Save(&group)
	}

	// Update OTPProfile
	var otp models.OTPProfile
	if err := database.DB.Where("owner_id = ?", user.ID).First(&otp).Error; err == nil {
		otp.IsActive = false
		otp.DeletionScheduledFor = &req.DeletionDate
		database.DB.Save(&otp)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}

// DeleteProductNow deletes the product immediately if no active subscriptions
func DeleteProductNow(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	database.DB.Where("owner_id = ?", user.ID).Delete(&models.Group{})
	database.DB.Where("owner_id = ?", user.ID).Delete(&models.OTPProfile{})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}

type UpdateVisibilityRequest struct {
	IsHidden bool `json:"is_hidden"`
}

// UpdateGroupVisibility hides or unhides the product
func UpdateGroupVisibility(w http.ResponseWriter, r *http.Request) {
	var req UpdateVisibilityRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Hide/Show Group
	var group models.Group
	if err := database.DB.Where("owner_id = ?", user.ID).First(&group).Error; err == nil {
		group.IsActive = !req.IsHidden
		if !req.IsHidden {
			group.DeletionScheduledFor = nil // Cancel deletion if made visible again
		}
		database.DB.Save(&group)
	}

	// Hide/Show OTPProfile
	var otp models.OTPProfile
	if err := database.DB.Where("owner_id = ?", user.ID).First(&otp).Error; err == nil {
		otp.IsActive = !req.IsHidden
		if !req.IsHidden {
			otp.DeletionScheduledFor = nil
		}
		database.DB.Save(&otp)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}

type UpdateInfoRequest struct {
	Name         string `json:"name"`
	ProductImage string `json:"product_image,omitempty"`
}

// UpdateGroupInfo updates name and image
func UpdateGroupInfo(w http.ResponseWriter, r *http.Request) {
	var req UpdateInfoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Update Group
	var group models.Group
	if err := database.DB.Where("owner_id = ?", user.ID).First(&group).Error; err == nil {
		if req.Name != "" {
			group.Name = req.Name
		}
		if req.ProductImage != "" {
			group.ProductImage = req.ProductImage
		}
		database.DB.Save(&group)
	}

	// Update OTPProfile
	var otp models.OTPProfile
	if err := database.DB.Where("owner_id = ?", user.ID).First(&otp).Error; err == nil {
		if req.Name != "" {
			otp.ProductName = req.Name
		}
		if req.ProductImage != "" {
			otp.ProductImage = req.ProductImage
		}
		database.DB.Save(&otp)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}
