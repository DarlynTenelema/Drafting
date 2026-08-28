package handlers

import (
	"encoding/json"
	"net/http"

	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/middleware"
	"backend/internal/models"
	"backend/internal/utils"
	"log"
	"time"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

// SubmitTicket creates a new support ticket and its first message
func SubmitTicket(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserIDFromContext(r.Context())
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req struct {
		Subject    string `json:"subject"`
		TicketType string `json:"ticket_type"`
		Priority   string `json:"priority"`
		Message    string `json:"message"`
		EvidenceURL string `json:"evidence_url"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// AI Triage to automatically determine priority
	urgency, _, err := gemini.CategorizeTicket(r.Context(), req.Subject + "\n" + req.Message)
	if err != nil {
		urgency = "high" // Default fallback
	}
	req.Priority = urgency

	db := database.GetDB()
	
	// Create Ticket
	ticket := models.Ticket{
		UserID:     userID,
		Subject:    req.Subject,
		TicketType: req.TicketType,
		Priority:   req.Priority,
		Status:     "open",
	}

	tx := db.Begin()
	if err := tx.Create(&ticket).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to create ticket", http.StatusInternalServerError)
		return
	}

	// Create First Message
	message := models.TicketMessage{
		TicketID:    ticket.ID,
		SenderID:    userID,
		Message:     req.Message,
		EvidenceURL: req.EvidenceURL,
	}

	if err := tx.Create(&message).Error; err != nil {
		tx.Rollback()
		http.Error(w, "Failed to save message", http.StatusInternalServerError)
		return
	}

	tx.Commit()

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(ticket)
}

// GetMyTickets lists tickets created by the user
func GetMyTickets(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserIDFromContext(r.Context())
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	db := database.GetDB()
	var tickets []models.Ticket

	if err := db.Where("user_id = ?", userID).Order("created_at desc").Find(&tickets).Error; err != nil {
		http.Error(w, "Failed to fetch tickets", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tickets)
}

// GetMyTicketMessages gets messages for a specific ticket if it belongs to the user
func GetMyTicketMessages(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserIDFromContext(r.Context())
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	ticketID := chi.URLParam(r, "id")
	db := database.GetDB()

	// Verify ownership
	var ticket models.Ticket
	if err := db.Where("id = ? AND user_id = ?", ticketID, userID).First(&ticket).Error; err != nil {
		http.Error(w, "Ticket not found or unauthorized", http.StatusNotFound)
		return
	}

	var messages []models.TicketMessage
	// Hide internal notes from user
	if err := db.Preload("Sender").Where("ticket_id = ? AND is_internal_note = ?", ticketID, false).Order("created_at asc").Find(&messages).Error; err != nil {
		http.Error(w, "Failed to fetch messages", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(messages)
}

// UserReplyTicket allows the user to send a new message to their ticket
func UserReplyTicket(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserIDFromContext(r.Context())
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	ticketID := chi.URLParam(r, "id")
	var req struct {
		Message string `json:"message"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if utils.HasHiddenAbbreviations(req.Message) {
		http.Error(w, "Tu mensaje contiene abreviaciones ocultas o falta de vocales. Por favor escribe las palabras completas.", http.StatusBadRequest)
		return
	}

	action, reason, err := gemini.AnalyzeToxicity(r.Context(), req.Message)
	if err == nil && action == "STRIKE" {
		log.Printf("AI Strike in Ticket Reply: %s", reason)
		var user models.User
		database.GetDB().Where("id = ?", userID).First(&user)
		newStrikes := user.Strikes + 1
		updates := map[string]interface{}{"strikes": newStrikes}
		if newStrikes >= 3 {
			updates["is_pending_ban"] = true
			banDate := time.Now().Add(7 * 24 * time.Hour)
			updates["pending_ban_until"] = &banDate
		}
		database.GetDB().Model(&user).Updates(updates)
		http.Error(w, "Tu respuesta viola las reglas de la comunidad y se te ha aplicado un strike.", http.StatusBadRequest)
		return
	}

	db := database.GetDB()

	// Verify ownership
	var ticket models.Ticket
	if err := db.Where("id = ? AND user_id = ?", ticketID, userID).First(&ticket).Error; err != nil {
		http.Error(w, "Ticket not found or unauthorized", http.StatusNotFound)
		return
	}

	// Update ticket status to open if it was resolved, because user is replying
	if ticket.Status == "resolved" {
		db.Model(&ticket).Update("status", "open")
	}

	msg := models.TicketMessage{
		TicketID: uuid.MustParse(ticketID),
		SenderID: userID,
		Message:  req.Message,
	}

	if err := db.Create(&msg).Error; err != nil {
		http.Error(w, "Failed to send message", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(msg)
}

// SubmitSuggestion creates a new idea in the suggestion box
func SubmitSuggestion(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserIDFromContext(r.Context())
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req struct {
		Title       string `json:"title"`
		Category    string `json:"category"`
		Description string `json:"description"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	db := database.GetDB()
	
	suggestion := models.Suggestion{
		UserID:      userID,
		Title:       req.Title,
		Category:    req.Category,
		Description: req.Description,
	}

	if err := db.Create(&suggestion).Error; err != nil {
		http.Error(w, "Failed to submit suggestion", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(suggestion)
}
