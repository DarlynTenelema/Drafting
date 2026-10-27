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

	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS purchased_queries integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_queries integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_plan varchar(50) DEFAULT 'none'`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_ends_at timestamp with time zone`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS has_purchased_starter boolean DEFAULT false`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_transferred_today integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_transfer_date varchar(10) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_received_today integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_received_date varchar(10) DEFAULT ''`)

	// Tablas de Tienda, Transacciones y Transferencias (Garantizadas en Producción)
	db.Exec(`CREATE TABLE IF NOT EXISTS transactions (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		user_id uuid NOT NULL,
		type varchar(50) NOT NULL,
		item_key varchar(50) NOT NULL,
		amount_usd decimal(10,2) NOT NULL,
		queries_added integer NOT NULL,
		provider varchar(50) DEFAULT 'google_play',
		provider_transaction_id varchar(255),
		status varchar(50) DEFAULT 'completed',
		created_at timestamp with time zone,
		deleted_at timestamp with time zone
	)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions(user_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_transactions_provider_tx_id ON transactions(provider_transaction_id)`)

	db.Exec(`CREATE TABLE IF NOT EXISTS query_transfers (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		sender_id uuid NOT NULL,
		from_referral_code varchar(16),
		receiver_id uuid NOT NULL,
		to_referral_code varchar(16),
		amount integer NOT NULL,
		created_at timestamp with time zone,
		deleted_at timestamp with time zone
	)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_query_transfers_sender ON query_transfers(sender_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_query_transfers_receiver ON query_transfers(receiver_id)`)

	// Auto Migrate seguro para sincronizar modelos
	err = db.AutoMigrate(
		&models.User{},
		&models.ApiUsage{},
		&models.Transaction{},
		&models.QueryTransfer{},
	)
	if err != nil {
		log.Printf("Warning: Non-fatal AutoMigrate notice: %v", err)
	}

	DB = db
}
