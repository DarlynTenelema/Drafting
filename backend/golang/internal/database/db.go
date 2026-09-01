package database

import (
	"log"
	"time"

	"backend/internal/config"
	"backend/internal/models"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var DB *gorm.DB

func GetDB() *gorm.DB {
	return DB
}

func Connect() {
	dsn := config.GetEnv("DATABASE_URL", "host=localhost user=postgres password=postgres dbname=draft port=5432 sslmode=disable")
	
	db, err := gorm.Open(postgres.New(postgres.Config{
		DSN:                  dsn,
		PreferSimpleProtocol: true, // disable implicit prepared statement usage
	}), &gorm.Config{})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		log.Fatalf("Failed to get sql.DB: %v", err)
	}
	
	// Configuración para Producción (Connection Pooling)
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(100)
	sqlDB.SetConnMaxLifetime(time.Hour)

	log.Println("Connected to the database successfully.")

	// Auto Migrate the schema conditionally for production safety
	if config.GetEnv("DB_AUTO_MIGRATE", "false") == "true" || config.GetEnv("ENV", "development") != "production" {
		err = db.AutoMigrate(
			&models.User{},
			&models.SubscriptionPlan{},
			&models.PaymentTransaction{},
			&models.ApiUsage{},
			&models.Group{},
			&models.OTPProfile{},
			&models.Wallet{},
			&models.Transaction{},
			&models.Channel{},
			&models.VideoEmbed{},
			&models.CreatorProfile{},
			&models.Fanart{},
			&models.Report{},
			&models.IdentityVerification{},
			&models.ContentReport{},
			&models.Comment{},
			&models.VideoLike{},
			&models.Subscription{},
			&models.AIModel{},
			&models.MatchSession{},
			&models.MatchScreenshot{},
			&models.MatchChatThread{},
			&models.MatchChatMessage{},
		)
		if err != nil {
			log.Fatalf("Failed to auto migrate database: %v", err)
		}
	} else {
		log.Println("Skipping AutoMigrate in production environment.")
	}

	DB = db

	seedSubscriptionPlans()
}
