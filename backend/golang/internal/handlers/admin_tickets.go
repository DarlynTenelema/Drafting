package handlers

import (
	"encoding/json"
	"net/http"

	"backend/internal/database"
	"backend/internal/models"
	"backend/internal/middleware"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

// GetTickets returns a list of tickets, optionally filtered by status
func GetTickets(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	var tickets []models.Ticket

	status := r.URL.Query().Get("status")
	query := db.Preload("User").Preload("AssignedAdmin").Order("created_at desc")
	
	if status != "" {
		query = query.Where("status = ?", status)
	}

	if err := query.Find(&tickets).Error; err != nil {
		http.Error(w, "Failed to fetch tickets", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tickets)
}

// GetTicketMessages returns the thread of a specific ticket
func GetTicketMessages(w http.ResponseWriter, r *http.Request) {
	ticketID := chi.URLParam(r, "id")
	
	db := database.GetDB()
	var messages []models.TicketMessage

	if err := db.Preload("Sender").Where("ticket_id = ?", ticketID).Order("created_at asc").Find(&messages).Error; err != nil {
		http.Error(w, "Failed to fetch messages", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(messages)
}

// UpdateTicketStatus changes the status or priority of a ticket
func UpdateTicketStatus(w http.ResponseWriter, r *http.Request) {
	ticketID := chi.URLParam(r, "id")
	
	var req struct {
		Status   string `json:"status"`
		Priority string `json:"priority"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	db := database.GetDB()
	
	updates := map[string]interface{}{}
	if req.Status != "" {
		updates["status"] = req.Status
	}
	if req.Priority != "" {
		updates["priority"] = req.Priority
	}

	if err := db.Model(&models.Ticket{}).Where("id = ?", ticketID).Updates(updates).Error; err != nil {
		http.Error(w, "Failed to update ticket", http.StatusInternalServerError)
		return
	}

	// Optionally create Audit Log here...
	// ...

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Ticket updated successfully"})
}

// ReplyTicket adds a new message to the ticket from the admin
func ReplyTicket(w http.ResponseWriter, r *http.Request) {
	ticketID := chi.URLParam(r, "id")
	
	// Get admin ID from context
	admin, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req struct {
		Message        string `json:"message"`
		IsInternalNote bool   `json:"is_internal_note"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	parsedTicketID, err := uuid.Parse(ticketID)
	if err != nil {
		http.Error(w, "Invalid ticket ID", http.StatusBadRequest)
		return
	}

	msg := models.TicketMessage{
		TicketID:       parsedTicketID,
		SenderID:       admin.ID,
		Message:        req.Message,
		IsInternalNote: req.IsInternalNote,
	}

	db := database.GetDB()
	if err := db.Create(&msg).Error; err != nil {
		http.Error(w, "Failed to save message", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(msg)
}
