package main

import (
	"log"
	"time"

	"backend/internal/config"
	"backend/internal/database"
	"backend/internal/models"
)

func main() {
	config.Load()
	database.Connect()

	// Update all users or just the most recent to have ultra
	var user models.User
	if err := database.DB.Order("created_at desc").First(&user).Error; err != nil {
		log.Fatalf("No users found: %v", err)
	}

	plan := "ultra"
	endsAt := time.Now().Add(30 * 24 * time.Hour)
	user.ActivePlan = &plan
	user.SubscriptionEndsAt = &endsAt

	if err := database.DB.Save(&user).Error; err != nil {
		log.Fatalf("Failed to update user: %v", err)
	}

	log.Printf("User %s updated to Ultra ending at %v", user.Email, endsAt)
}
