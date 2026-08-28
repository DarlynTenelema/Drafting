package handlers

import (
	"encoding/json"
	"net/http"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"

	"github.com/google/uuid"
)

type VerifyIdentityRequest struct {
	ChannelID string `json:"channel_id"`
	ProofURL  string `json:"proof_url"`
}

func VerifyIdentity(w http.ResponseWriter, r *http.Request) {
	var req VerifyIdentityRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	chanUUID, err := uuid.Parse(req.ChannelID)
	if err != nil {
		http.Error(w, "Invalid channel ID", http.StatusBadRequest)
		return
	}

	var channel models.Channel
	if err := database.DB.Where("id = ? AND owner_id = ?", chanUUID, user.ID).First(&channel).Error; err != nil {
		http.Error(w, "Channel not found or unauthorized", http.StatusNotFound)
		return
	}

	verification := models.IdentityVerification{
		ChannelID: channel.ID,
		ProofURL:  req.ProofURL,
		Status:    "pending",
	}

	if err := database.DB.Create(&verification).Error; err != nil {
		http.Error(w, "Failed to submit verification", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
}

type ReportContentRequest struct {
	VideoID  string `json:"video_id"`
	Reason   string `json:"reason"`
	ProofURL string `json:"proof_url"`
}

func ReportContent(w http.ResponseWriter, r *http.Request) {
	var req ReportContentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	vidUUID, err := uuid.Parse(req.VideoID)
	if err != nil {
		http.Error(w, "Invalid video ID", http.StatusBadRequest)
		return
	}

	report := models.ContentReport{
		VideoID:    vidUUID,
		ReporterID: user.ID,
		Reason:     req.Reason,
		ProofURL:   req.ProofURL,
		Status:     "pending",
	}

	if err := database.DB.Create(&report).Error; err != nil {
		http.Error(w, "Failed to submit report", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
}


