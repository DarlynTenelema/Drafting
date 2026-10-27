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
		user_id uuid,
		type varchar(50) NOT NULL DEFAULT 'pack',
		item_key varchar(50) NOT NULL DEFAULT '',
		amount_usd decimal(10,2) NOT NULL DEFAULT 0.00,
		queries_added integer NOT NULL DEFAULT 0,
		provider varchar(50) DEFAULT 'google_play',
		provider_transaction_id varchar(255),
		status varchar(50) DEFAULT 'completed',
		created_at timestamp with time zone,
		deleted_at timestamp with time zone
	)`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS user_id uuid`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS type varchar(50) DEFAULT 'pack'`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS item_key varchar(50) DEFAULT ''`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS amount_usd decimal(10,2) DEFAULT 0.00`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS queries_added integer DEFAULT 0`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS provider varchar(50) DEFAULT 'google_play'`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS provider_transaction_id varchar(255)`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS status varchar(50) DEFAULT 'completed'`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS created_at timestamp with time zone`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone`)

	db.Exec(`CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions(user_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_transactions_provider_tx_id ON transactions(provider_transaction_id)`)

	db.Exec(`CREATE TABLE IF NOT EXISTS query_transfers (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		from_user_id uuid,
		from_referral_code varchar(16),
		to_user_id uuid,
		to_referral_code varchar(16),
		amount integer NOT NULL DEFAULT 0,
		created_at timestamp with time zone,
		deleted_at timestamp with time zone
	)`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS sender_id uuid`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS from_user_id uuid`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS from_referral_code varchar(16)`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS receiver_id uuid`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS to_user_id uuid`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS to_referral_code varchar(16)`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS amount integer DEFAULT 0`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS created_at timestamp with time zone`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone`)

	db.Exec(`CREATE INDEX IF NOT EXISTS idx_query_transfers_sender ON query_transfers(from_user_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_query_transfers_receiver ON query_transfers(to_user_id)`)

	// Acreditación y reparación para la compra del Pack Starter (Orden GPA.3372-9089-9136-22405)
	db.Exec(`UPDATE users 
		SET available_queries = available_queries + 50, 
		    purchased_queries = purchased_queries + 50, 
		    has_purchased_starter = true 
		WHERE id = '527e0507-28ea-4548-b51e-a3458871cd1b' 
		  AND has_purchased_starter = false`)

	db.Exec(`INSERT INTO transactions (id, user_id, type, item_key, amount_usd, queries_added, provider, provider_transaction_id, status, created_at)
		VALUES (gen_random_uuid(), '527e0507-28ea-4548-b51e-a3458871cd1b', 'pack', 'pack_starter', 0.19, 50, 'google_play', 'GPA.3372-9089-9136-22405', 'completed', NOW())
		ON CONFLICT DO NOTHING`)

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
