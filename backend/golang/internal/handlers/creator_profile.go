package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
)

type CreateCreatorProfileRequest struct {
	ArtistName string `json:"artist_name"`
	Tags       string `json:"tags"` // comma-separated
}

// CreateCreatorProfile handles the creation of a creator profile
func CreateCreatorProfile(w http.ResponseWriter, r *http.Request) {
	var req CreateCreatorProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	req.ArtistName = strings.TrimSpace(req.ArtistName)
	if req.ArtistName == "" {
		http.Error(w, "Artist name is required", http.StatusBadRequest)
		return
	}

	// Validate max 5 tags
	tagsList := strings.Split(req.Tags, ",")
	validTags := []string{}
	for _, t := range tagsList {
		trimmed := strings.TrimSpace(t)
		if trimmed != "" {
			validTags = append(validTags, trimmed)
		}
	}
	if len(validTags) > 5 {
		http.Error(w, "Maximum of 5 tags allowed", http.StatusBadRequest)
		return
	}
	finalTags := strings.Join(validTags, ",")

	// Check if the user already has a profile
	var existingProfile models.CreatorProfile
	if err := database.DB.Where("user_id = ?", user.ID).First(&existingProfile).Error; err == nil {
		http.Error(w, "Creator profile already exists", http.StatusConflict)
		return
	}

	// Check if artist name is taken
	var nameCheck models.CreatorProfile
	if err := database.DB.Where("artist_name = ?", req.ArtistName).First(&nameCheck).Error; err == nil {
		http.Error(w, "Artist name is already taken", http.StatusConflict)
		return
	}

	profile := models.CreatorProfile{
		UserID:     user.ID,
		ArtistName: req.ArtistName,
		Tags:       finalTags,
	}

	if err := database.DB.Create(&profile).Error; err != nil {
		http.Error(w, "Failed to create creator profile", http.StatusInternalServerError)
		return
	}

	// Optionally update user role to 'creator' if they were just a 'consumer'
	if user.Role == "consumer" {
		user.Role = "creator"
		database.DB.Save(user)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(profile)
}

// GetCreatorProfile retrieves the profile for the current user
func GetCreatorProfile(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var profile models.CreatorProfile
	if err := database.DB.Where("user_id = ?", user.ID).First(&profile).Error; err != nil {
		http.Error(w, "Creator profile not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(profile)
}
