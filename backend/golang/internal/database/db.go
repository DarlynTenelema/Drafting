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

	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS available_queries integer DEFAULT 13`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_queries integer DEFAULT 3`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS bonus_queries integer DEFAULT 10`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS ad_queries integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_daily_reward_date varchar(10) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_code varchar(16) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS referred_by_id uuid`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_count integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_rewards_claimed integer DEFAULT 0`)

	// Asignar códigos únicos a usuarios existentes para que no tengan '' repetido
	db.Exec(`UPDATE users SET referral_code = 'WR' || UPPER(SUBSTRING(REPLACE(id::text, '-', ''), 1, 6)) WHERE referral_code IS NULL OR referral_code = ''`)

	// Backfill para usuarios existentes: garantizar que daily_queries tenga tope 3 y el resto en ad/bonus
	db.Exec(`UPDATE users SET daily_queries = 3, bonus_queries = LEAST(10, GREATEST(0, available_queries - 3)), ad_queries = GREATEST(0, available_queries - 13) WHERE daily_queries IS NULL OR daily_queries = 0`)

	// Auto Migrate the schema conditionally for production safety
	if config.GetEnv("DB_AUTO_MIGRATE", "false") == "true" || config.GetEnv("ENV", "development") != "production" {
		err = db.AutoMigrate(
			&models.User{},
			&models.ApiUsage{},
		)
		if err != nil {
			log.Printf("Warning: Non-fatal AutoMigrate notice: %v", err)
		}
	} else {
		log.Println("Skipping AutoMigrate in production environment.")
	}

	DB = db
}
