package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
	"github.com/go-chi/chi/v5"
)

// GetMyInvitations fetches all pending invitations for the logged-in user
func GetMyInvitations(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var invitations []models.GroupInvitation
	database.DB.Where("email = ? AND status = 'pending' AND expires_at > ?", user.Email, time.Now()).Find(&invitations)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(invitations)
}

// AcceptInvitation allows a user to accept a pending invite
func AcceptInvitation(w http.ResponseWriter, r *http.Request) {
	inviteID := chi.URLParam(r, "id")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var invite models.GroupInvitation
	if err := database.DB.Where("id = ? AND email = ?", inviteID, user.Email).First(&invite).Error; err != nil {
		http.Error(w, "Invitation not found or unauthorized", http.StatusNotFound)
		return
	}

	if invite.Status != "pending" || invite.ExpiresAt.Before(time.Now()) {
		http.Error(w, "Invitation expired or already processed", http.StatusBadRequest)
		return
	}

	invite.Status = "accepted"
	database.DB.Save(&invite)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}

// DeclineInvitation allows a user to decline a pending invite
func DeclineInvitation(w http.ResponseWriter, r *http.Request) {
	inviteID := chi.URLParam(r, "id")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var invite models.GroupInvitation
	if err := database.DB.Where("id = ? AND email = ?", inviteID, user.Email).First(&invite).Error; err != nil {
		http.Error(w, "Invitation not found or unauthorized", http.StatusNotFound)
		return
	}

	invite.Status = "declined"
	database.DB.Save(&invite)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}

// RevokeInvitation allows the group creator to revoke a pending invite
func RevokeInvitation(w http.ResponseWriter, r *http.Request) {
	inviteID := chi.URLParam(r, "id")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var invite models.GroupInvitation
	if err := database.DB.First(&invite, "id = ?", inviteID).Error; err != nil {
		http.Error(w, "Invitation not found", http.StatusNotFound)
		return
	}

	// Verify the user owns the group this invite belongs to
	var group models.Group
	if err := database.DB.Where("id = ? AND owner_id = ?", invite.GroupID, user.ID).First(&group).Error; err != nil {
		http.Error(w, "Unauthorized to revoke this invitation", http.StatusUnauthorized)
		return
	}

	database.DB.Delete(&invite)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}
