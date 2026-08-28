package handlers

import (
	"encoding/json"
	"net/http"

	"backend/internal/database"
	"backend/internal/models"
)

// DashboardStats struct for returning dashboard metrics
type DashboardStats struct {
	TotalUsers     int64 `json:"total_users"`
	ActiveReports  int64 `json:"active_reports"`
	TotalVideos    int64 `json:"total_videos"`
	TotalFanarts   int64 `json:"total_fanarts"`
}

func GetAdminDashboardStats(w http.ResponseWriter, r *http.Request) {
	db := database.GetDB()
	var stats DashboardStats

	// Count users
	db.Model(&models.User{}).Count(&stats.TotalUsers)

	// Count active reports (tickets that are not resolved or closed)
	db.Model(&models.Ticket{}).Where("status NOT IN ?", []string{"resolved", "closed"}).Count(&stats.ActiveReports)

	// Count total videos
	db.Model(&models.VideoEmbed{}).Count(&stats.TotalVideos)

	// Count total fanarts
	db.Model(&models.Fanart{}).Count(&stats.TotalFanarts)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}
