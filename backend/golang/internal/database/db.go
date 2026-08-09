package database

import (
	"log"

	"backend/internal/config"
	"backend/internal/models"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var DB *gorm.DB

func Connect() {
	dsn := config.GetEnv("DATABASE_URL", "host=localhost user=postgres password=postgres dbname=draft port=5432 sslmode=disable")
	
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	log.Println("Connected to the database successfully.")

	// Auto Migrate the schema
	err = db.AutoMigrate(
		&models.User{},
		&models.SubscriptionPlan{},
		&models.PaymentTransaction{},
	)
	if err != nil {
		log.Fatalf("Failed to auto migrate database: %v", err)
	}

	DB = db

	seedSubscriptionPlans()
}
