package main

import (
	"log"

	"backend/internal/config"
	"backend/internal/models"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func main() {
	// Initialize config and database manually to connect from a standalone script
	config.Load()
	dsn := config.GetEnv("DATABASE_URL", "host=localhost user=postgres password=postgres dbname=draft port=5432 sslmode=disable")
	
	db, err := gorm.Open(postgres.New(postgres.Config{
		DSN:                  dsn,
		PreferSimpleProtocol: true,
	}), &gorm.Config{})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	testEmails := []string{
		"darlyndavid2026@gmail.com", 
		"0805409802d@gmail.com",
	}

	for _, email := range testEmails {
		var user models.User
		if err := db.Where("email = ?", email).First(&user).Error; err != nil {
			log.Printf("Tester account %s not found in DB, skipping...\n", email)
			continue
		}

		log.Printf("Resetting tester account: %s (ID: %s)\n", email, user.ID)

		db.Where("user_id = ?", user.ID).Delete(&models.ApiUsage{})
		user.AvailableQueries = 5
		db.Save(&user)

		log.Printf("Successfully reset queries to 5 for: %s\n", email)
	}

	log.Println("Done resetting tester accounts! They are now basically fresh for new purchases.")
}
