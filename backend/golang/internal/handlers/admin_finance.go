package handlers

import (
	"encoding/json"
	"net/http"

	"backend/internal/database"
	"backend/internal/models"
	"github.com/go-chi/chi/v5"
)

// GetSuspiciousTransactions returns a list of transactions flagged for review
func GetSuspiciousTransactions(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	var transactions []models.SuspiciousTransaction

	status := r.URL.Query().Get("status")
	query := db.Preload("User").Order("created_at desc")
	
	if status != "" {
		query = query.Where("status = ?", status)
	}

	if err := query.Find(&transactions).Error; err != nil {
		http.Error(w, "Failed to fetch suspicious transactions", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(transactions)
}

// ResolveSuspiciousTransaction changes the status of a fraud flag
func ResolveSuspiciousTransaction(w http.ResponseWriter, r *http.Request) {
	txID := chi.URLParam(r, "id")
	
	var req struct {
		Status string `json:"status"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	db := database.GetDB()
	
	if err := db.Model(&models.SuspiciousTransaction{}).Where("id = ?", txID).Update("status", req.Status).Error; err != nil {
		http.Error(w, "Failed to update transaction status", http.StatusInternalServerError)
		return
	}

	// Si la transacción se marcó como "resolved_banned", podríamos disparar la lógica de banneo aquí.
	if req.Status == "resolved_banned" {
		var tx models.SuspiciousTransaction
		if err := db.Where("id = ?", txID).First(&tx).Error; err == nil {
			db.Model(&models.User{}).Where("id = ?", tx.UserID).Update("banned", true)
		}
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Transaction resolved successfully"})
}
