package database

import (
	"log"
	"strconv"
	"strings"
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
	
	// Configuración para Producción (Connection Pooling configurable para Supabase Free/Pro y VPS)
	maxIdle := 10
	if v, err := strconv.Atoi(strings.TrimSpace(config.GetEnv("DB_MAX_IDLE_CONNS", ""))); err == nil && v >= 2 && v <= 50 {
		maxIdle = v
	}
	maxOpen := 40
	if v, err := strconv.Atoi(strings.TrimSpace(config.GetEnv("DB_MAX_OPEN_CONNS", ""))); err == nil && v >= maxIdle && v <= 200 {
		maxOpen = v
	}
	sqlDB.SetMaxIdleConns(maxIdle)
	sqlDB.SetMaxOpenConns(maxOpen)
	sqlDB.SetConnMaxIdleTime(5 * time.Minute)
	sqlDB.SetConnMaxLifetime(time.Hour)

	log.Println("Connected to the database successfully.")

	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS available_queries integer DEFAULT 8`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_queries integer DEFAULT 3`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS bonus_queries integer DEFAULT 5`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS ad_queries integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_daily_reward_date varchar(10) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_code varchar(16) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS referred_by_id uuid`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_count integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_rewards_claimed integer DEFAULT 0`)

	// Asignar códigos únicos a usuarios existentes para que no tengan '' repetido
	db.Exec(`UPDATE users SET referral_code = 'WR' || UPPER(SUBSTRING(REPLACE(id::text, '-', ''), 1, 6)) WHERE referral_code IS NULL OR referral_code = ''`)

	// Backfill solo para usuarios legacy que nunca tuvieron desglose inicializado
	db.Exec(`UPDATE users SET daily_queries = 3, bonus_queries = LEAST(10, GREATEST(0, available_queries - 3)), ad_queries = GREATEST(0, available_queries - 13), last_daily_reward_date = TO_CHAR(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD') WHERE (last_daily_reward_date IS NULL OR last_daily_reward_date = '') AND (daily_queries IS NULL OR daily_queries = 0)`)

	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS purchased_queries integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_queries integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS gift_queries integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_plan varchar(50) DEFAULT 'none'`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_ends_at timestamp with time zone`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS has_purchased_starter boolean DEFAULT false`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_transferred_today integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_transfer_date varchar(10) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_received_today integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_received_date varchar(10) DEFAULT ''`)

	// Sincronizar available_queries con la suma real de bolsas para reparar cuentas de versiones anteriores
	db.Exec(`UPDATE users SET available_queries = GREATEST(0, COALESCE(daily_queries, 0) + COALESCE(bonus_queries, 0) + COALESCE(ad_queries, 0) + COALESCE(purchased_queries, 0) + COALESCE(subscription_queries, 0)) WHERE available_queries != GREATEST(0, COALESCE(daily_queries, 0) + COALESCE(bonus_queries, 0) + COALESCE(ad_queries, 0) + COALESCE(purchased_queries, 0) + COALESCE(subscription_queries, 0))`)

	// Billeteras independientes por modelo (Classic, Flake 1.0, Aureon 1.0)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS classic_daily integer DEFAULT 3`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS classic_ad integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS classic_purchased integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS classic_last_recharge_at timestamp with time zone`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS flake_ad integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS flake_purchased integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS flake_ads_today integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS flake_last_ad_date varchar(10) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS aureon_ad integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS aureon_purchased integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS aureon_ads_today integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS aureon_last_ad_date varchar(10) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS models_v2_migrated boolean DEFAULT false`)

	// Migración quirúrgica única para cuentas existentes:
	// - Resetea consultas gratuitas acumuladas (daily_queries y bonus_queries -> 0) y programa recarga de 3 Classic en 24h.
	// - Preserva 100% intactas las consultas compradas (purchased_queries + subscription_queries -> classic_purchased)
	//   y las consultas obtenidas por AdMob/referidos (ad_queries -> classic_ad).
	db.Exec(`UPDATE users
		SET
			classic_purchased = GREATEST(0, COALESCE(purchased_queries, 0) + COALESCE(subscription_queries, 0)),
			classic_ad = GREATEST(0, COALESCE(ad_queries, 0)),
			classic_daily = 0,
			classic_last_recharge_at = NOW(),
			daily_queries = 0,
			bonus_queries = 0,
			flake_ad = 0,
			flake_purchased = 0,
			flake_ads_today = 0,
			flake_last_ad_date = '',
			aureon_ad = 0,
			aureon_purchased = 0,
			aureon_ads_today = 0,
			aureon_last_ad_date = '',
			available_queries = GREATEST(0, COALESCE(purchased_queries, 0) + COALESCE(subscription_queries, 0) + COALESCE(ad_queries, 0)),
			models_v2_migrated = true
		WHERE COALESCE(models_v2_migrated, false) = false`)

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
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS purchase_token text DEFAULT ''`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS status varchar(50) DEFAULT 'completed'`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS created_at timestamp with time zone`)
	db.Exec(`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone`)

	db.Exec(`CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions(user_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_transactions_user_created ON transactions(user_id, created_at DESC)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_transactions_provider_tx_id ON transactions(provider_transaction_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_transactions_purchase_token ON transactions(purchase_token)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_users_device_banned ON users(device_id) WHERE banned = true AND device_id <> ''`)

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
	db.Exec(`ALTER TABLE query_transfers ALTER COLUMN sender_id DROP NOT NULL`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS from_user_id uuid`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS from_referral_code varchar(16)`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS receiver_id uuid`)
	db.Exec(`ALTER TABLE query_transfers ALTER COLUMN receiver_id DROP NOT NULL`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS to_user_id uuid`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS to_referral_code varchar(16)`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS amount integer DEFAULT 0`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS created_at timestamp with time zone`)
	db.Exec(`ALTER TABLE query_transfers ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone`)

	db.Exec(`CREATE INDEX IF NOT EXISTS idx_query_transfers_sender ON query_transfers(from_user_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_query_transfers_receiver ON query_transfers(to_user_id)`)

	// Columna para vincular usuarios con códigos de streamers afiliados
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS referred_by_streamer_code varchar(32) DEFAULT ''`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_users_referred_by_streamer ON users(referred_by_streamer_code)`)

	// Sistema de Trivia: Vidas y Tablas
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS trivia_lives integer DEFAULT 5`)
	db.Exec(`UPDATE users SET trivia_lives = 5 WHERE trivia_lives IS NULL OR trivia_lives < 0`)

	db.Exec(`CREATE TABLE IF NOT EXISTS trivia_questions (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		category varchar(32) NOT NULL,
		game varchar(32) DEFAULT 'wild_rift',
		question_text text NOT NULL,
		target_name varchar(128) NOT NULL,
		clues text DEFAULT '',
		options text DEFAULT '[]',
		correct_answer text NOT NULL,
		tolerance integer DEFAULT 0,
		month_tag varchar(32) DEFAULT 'general',
		active boolean DEFAULT true,
		created_at timestamp with time zone,
		updated_at timestamp with time zone,
		deleted_at timestamp with time zone
	)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_trivia_questions_cat_act ON trivia_questions(category, active)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_trivia_questions_month ON trivia_questions(month_tag)`)

	db.Exec(`CREATE TABLE IF NOT EXISTS trivia_user_progress (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		user_id uuid NOT NULL,
		question_id uuid NOT NULL,
		category varchar(32) NOT NULL,
		is_correct boolean DEFAULT false,
		attempts_count integer DEFAULT 1,
		last_attempt_at timestamp with time zone,
		created_at timestamp with time zone,
		updated_at timestamp with time zone
	)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_trivia_user_progress_user ON trivia_user_progress(user_id, category)`)
	db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_trivia_user_question ON trivia_user_progress(user_id, question_id)`)

	// Sistema de Reels Tácticos: Tablas, Contadores y Rendimiento
	db.Exec(`CREATE TABLE IF NOT EXISTS reels (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		creator_id uuid NOT NULL,
		title varchar(180) NOT NULL,
		description text DEFAULT '',
		video_url text NOT NULL,
		thumbnail_url text DEFAULT '',
		duration_seconds integer DEFAULT 30,
		game_mode varchar(32) DEFAULT 'wild_rift',
		category varchar(32) DEFAULT 'jugadas',
		language varchar(10) DEFAULT 'universal',
		champion_name varchar(64) DEFAULT '',
		likes_count integer DEFAULT 0,
		comments_count integer DEFAULT 0,
		saves_count integer DEFAULT 0,
		views_count integer DEFAULT 0,
		trend_score numeric DEFAULT 0.0,
		active boolean DEFAULT true,
		created_at timestamp with time zone DEFAULT NOW(),
		updated_at timestamp with time zone DEFAULT NOW(),
		deleted_at timestamp with time zone
	)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reels_feed ON reels(active, language, trend_score DESC)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reels_creator ON reels(creator_id, created_at DESC)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reels_cat_mode ON reels(category, game_mode)`)

	db.Exec(`CREATE TABLE IF NOT EXISTS reel_likes (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		reel_id uuid NOT NULL,
		user_id uuid NOT NULL,
		created_at timestamp with time zone DEFAULT NOW()
	)`)
	db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS uq_reel_user_like ON reel_likes(reel_id, user_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reel_likes_user ON reel_likes(user_id)`)

	db.Exec(`CREATE TABLE IF NOT EXISTS reel_saves (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		reel_id uuid NOT NULL,
		user_id uuid NOT NULL,
		created_at timestamp with time zone DEFAULT NOW()
	)`)
	db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS uq_reel_user_save ON reel_saves(reel_id, user_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reel_saves_user ON reel_saves(user_id)`)

	db.Exec(`CREATE TABLE IF NOT EXISTS reel_comments (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		reel_id uuid NOT NULL,
		user_id uuid NOT NULL,
		content varchar(400) NOT NULL,
		created_at timestamp with time zone DEFAULT NOW(),
		updated_at timestamp with time zone DEFAULT NOW(),
		deleted_at timestamp with time zone
	)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reel_comments_reel ON reel_comments(reel_id, created_at ASC)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reel_comments_user ON reel_comments(user_id)`)

	db.Exec(`CREATE TABLE IF NOT EXISTS reel_views (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		reel_id uuid NOT NULL,
		user_id uuid,
		ip_hash varchar(64) DEFAULT '',
		watched_seconds integer DEFAULT 0,
		watched_percent integer DEFAULT 0,
		verified boolean DEFAULT false,
		created_at timestamp with time zone DEFAULT NOW()
	)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reel_views_reel ON reel_views(reel_id, created_at DESC)`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS video_key text DEFAULT ''`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS file_size_bytes bigint DEFAULT 0`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS width integer DEFAULT 0`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS height integer DEFAULT 0`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS orientation varchar(16) DEFAULT 'portrait'`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS verified_views_count integer DEFAULT 0`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS reports_count integer DEFAULT 0`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS silenced_by_reports boolean DEFAULT false`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS moderation_status varchar(32) DEFAULT 'approved'`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS moderation_reason varchar(160) DEFAULT ''`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS moderation_score numeric(5,4) DEFAULT 0.0`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS moderation_checked_at timestamp with time zone`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS content_hash varchar(128) DEFAULT ''`)
	db.Exec(`ALTER TABLE reels ADD COLUMN IF NOT EXISTS weighted_reports_score numeric(8,2) DEFAULT 0.0`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reels_moderation_status ON reels(moderation_status, updated_at DESC)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reels_content_hash ON reels(content_hash) WHERE content_hash <> ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS moderation_strikes integer DEFAULT 0`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS report_trust_score numeric(4,2) DEFAULT 1.0`)
	db.Exec(`ALTER TABLE reel_views ADD COLUMN IF NOT EXISTS watched_percent integer DEFAULT 0`)
	db.Exec(`ALTER TABLE reel_views ADD COLUMN IF NOT EXISTS verified boolean DEFAULT false`)
	db.Exec(`ALTER TABLE reel_views ADD COLUMN IF NOT EXISTS device_id varchar(255) DEFAULT ''`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reel_views_reel_ip ON reel_views(reel_id, ip_hash) WHERE ip_hash <> ''`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reel_views_reel_device ON reel_views(reel_id, device_id) WHERE device_id <> ''`)
	// Deduplicar vistas previas del mismo usuario antes de crear el índice único parcial
	db.Exec(`DELETE FROM reel_views a USING reel_views b WHERE a.user_id IS NOT NULL AND a.reel_id = b.reel_id AND a.user_id = b.user_id AND a.ctid < b.ctid`)
	db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS uq_reel_views_reel_user ON reel_views(reel_id, user_id) WHERE user_id IS NOT NULL`)

	// Perfil social de creadores (Bio + Twitch/TikTok/YouTube/Instagram/Kick) y vistas verificadas históricas
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS bio varchar(220) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS twitch_url varchar(255) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS tiktok_url varchar(255) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS youtube_url varchar(255) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS instagram_url varchar(255) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS kick_url varchar(255) DEFAULT ''`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS lifetime_verified_views bigint DEFAULT 0`)
	// Backfill seguro: garantiza que creadores con vistas verificadas previas las conserven aunque borren un reel
	db.Exec(`UPDATE users u
		SET lifetime_verified_views = sub.total_v
		FROM (
			SELECT creator_id, COALESCE(SUM(verified_views_count), 0) AS total_v
			FROM reels
			GROUP BY creator_id
		) sub
		WHERE u.id = sub.creator_id
		  AND COALESCE(u.lifetime_verified_views, 0) < sub.total_v`)

	// Sistema de seguidores reales
	db.Exec(`CREATE TABLE IF NOT EXISTS user_follows (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		follower_id uuid NOT NULL,
		following_id uuid NOT NULL,
		created_at timestamp with time zone DEFAULT NOW()
	)`)
	db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS uq_user_follow_pair ON user_follows(follower_id, following_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_user_follows_following ON user_follows(following_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_user_follows_follower ON user_follows(follower_id)`)

	// Sistema de retiros de creadores (mínimo $100 USD)
	db.Exec(`CREATE TABLE IF NOT EXISTS creator_payout_requests (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		user_id uuid NOT NULL,
		amount_usd numeric(12,4) NOT NULL,
		verified_views_snapshot bigint DEFAULT 0,
		payout_method varchar(32) NOT NULL DEFAULT 'paypal',
		payout_destination varchar(255) NOT NULL,
		status varchar(32) NOT NULL DEFAULT 'pending',
		admin_notes varchar(300) DEFAULT '',
		created_at timestamp with time zone DEFAULT NOW(),
		updated_at timestamp with time zone DEFAULT NOW()
	)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_creator_payouts_user ON creator_payout_requests(user_id, created_at DESC)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_creator_payouts_status ON creator_payout_requests(status, created_at DESC)`)

	db.Exec(`CREATE TABLE IF NOT EXISTS reel_reports (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		reel_id uuid NOT NULL,
		user_id uuid NOT NULL,
		reason varchar(64) NOT NULL DEFAULT 'other',
		details varchar(300) DEFAULT '',
		weight numeric(4,2) NOT NULL DEFAULT 1.0,
		created_at timestamp with time zone DEFAULT NOW()
	)`)
	db.Exec(`ALTER TABLE reel_reports ADD COLUMN IF NOT EXISTS weight numeric(4,2) NOT NULL DEFAULT 1.0`)
	db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS uq_reel_user_report ON reel_reports(reel_id, user_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_reel_reports_reel ON reel_reports(reel_id, created_at DESC)`)

	db.Exec(`CREATE TABLE IF NOT EXISTS banned_content_hashes (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		frame_hash varchar(64) NOT NULL,
		reason varchar(64) NOT NULL DEFAULT 'nsfw_gore',
		source_reel_id uuid,
		created_at timestamp with time zone DEFAULT NOW()
	)`)
	db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS uq_banned_content_frame_hash ON banned_content_hashes(frame_hash)`)

	db.Exec(`CREATE TABLE IF NOT EXISTS user_blocks (
		id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		blocker_id uuid NOT NULL,
		blocked_id uuid NOT NULL,
		created_at timestamp with time zone DEFAULT NOW()
	)`)
	db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS uq_user_block_pair ON user_blocks(blocker_id, blocked_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON user_blocks(blocker_id)`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON user_blocks(blocked_id)`)

	// Auto Migrate seguro para sincronizar modelos (incluyendo Fase 2: Streamers, Patrocinadores, Torneo C.L.A, Comunidad y Reels)
	err = db.AutoMigrate(
		&models.User{},
		&models.ApiUsage{},
		&models.Transaction{},
		&models.QueryTransfer{},
		&models.StreamerApplication{},
		&models.StreamerCommission{},
		&models.SponsorInquiry{},
		&models.TournamentRegistration{},
		&models.CommunityVote{},
		&models.NewsletterSubscriber{},
		&models.FeaturedPromotion{},
		&models.AppEvent{},
		&models.SocialLinkConfig{},
		&models.AppVersionConfig{},
		&models.DonorProfile{},
		&models.TriviaQuestion{},
		&models.TriviaUserProgress{},
		&models.Reel{},
		&models.ReelLike{},
		&models.ReelSave{},
		&models.ReelComment{},
		&models.ReelView{},
		&models.ReelReport{},
		&models.BannedContentHash{},
		&models.UserBlock{},
		&models.UserFollow{},
		&models.CreatorPayoutRequest{},
	)
	if err != nil {
		log.Printf("Warning: Non-fatal AutoMigrate notice: %v", err)
	}

	// Semillas iniciales para promociones destacadas si la tabla está vacía
	var promoCount int64
	db.Model(&models.FeaturedPromotion{}).Count(&promoCount)
	if promoCount == 0 {
		defaultPromos := []models.FeaturedPromotion{
			{
				Title:     "SC XXIII Oficial",
				Subtitle:  "Organizador Oficial de la Copa Latino Americana Anónima (C.L.A) • Sorteos y Transmisiones",
				Platform:  "Facebook Gaming",
				StreamURL: "https://www.facebook.com/profile.php?id=61556052170755",
				BadgeText: "ORGANIZADOR OFICIAL C.L.A",
				PromoCode: "SC23CLA",
				IsLive:    true,
				Active:    true,
				Priority:  10,
			},
			{
				Title:     "Convocatoria Casters C.L.A",
				Subtitle:  "¿Narrarás los Octavos de Final el 6 de Diciembre? Postúlate y patrocina tu canal",
				Platform:  "Twitch / TikTok Live",
				StreamURL: "/torneo",
				BadgeText: "CONVOCATORIA ABIERTA",
				PromoCode: "CASTERCLA",
				IsLive:    true,
				Active:    true,
				Priority:  8,
			},
		}
		for _, p := range defaultPromos {
			db.Create(&p)
		}
	}

	seedInitialTrivia(db)

	DB = db
}

func seedInitialTrivia(db *gorm.DB) {
	var count int64
	db.Model(&models.TriviaQuestion{}).Count(&count)
	if count > 0 {
		return
	}

	initialQuestions := []models.TriviaQuestion{
		// Criterio 1: ¿Cuánto cuesta este objeto? (item_cost)
		{
			Category:      models.TriviaCategoryItemCost,
			Game:          "wild_rift",
			QuestionText:  "¿Cuánto cuesta este objeto?",
			TargetName:    "Fuerza de la Trinidad",
			CorrectAnswer: "3333",
			Tolerance:     0,
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryItemCost,
			Game:          "wild_rift",
			QuestionText:  "¿Cuánto cuesta este objeto?",
			TargetName:    "Hoja del Rey Arruinado",
			CorrectAnswer: "3200",
			Tolerance:     0,
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryItemCost,
			Game:          "wild_rift",
			QuestionText:  "¿Cuánto cuesta este objeto?",
			TargetName:    "Filo del Infinito",
			CorrectAnswer: "3400",
			Tolerance:     0,
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryItemCost,
			Game:          "wild_rift",
			QuestionText:  "¿Cuánto cuesta este objeto?",
			TargetName:    "Sombrero Mortal de Rabadon",
			CorrectAnswer: "3500",
			Tolerance:     0,
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryItemCost,
			Game:          "wild_rift",
			QuestionText:  "¿Cuánto cuesta este objeto?",
			TargetName:    "Cuchilla Oscura",
			CorrectAnswer: "3000",
			Tolerance:     0,
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryItemCost,
			Game:          "wild_rift",
			QuestionText:  "¿Cuánto cuesta este objeto?",
			TargetName:    "Guantelete de Hielo",
			CorrectAnswer: "2700",
			Tolerance:     0,
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryItemCost,
			Game:          "wild_rift",
			QuestionText:  "¿Cuánto cuesta este objeto?",
			TargetName:    "Calibrador de Sterak",
			CorrectAnswer: "3200",
			Tolerance:     0,
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryItemCost,
			Game:          "wild_rift",
			QuestionText:  "¿Cuánto cuesta este objeto?",
			TargetName:    "Morellonomicón",
			CorrectAnswer: "2600",
			Tolerance:     0,
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryItemCost,
			Game:          "wild_rift",
			QuestionText:  "¿Cuánto cuesta este objeto?",
			TargetName:    "Corazón de Hielo",
			CorrectAnswer: "2700",
			Tolerance:     0,
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryItemCost,
			Game:          "wild_rift",
			QuestionText:  "¿Cuánto cuesta este objeto?",
			TargetName:    "Sanguinaria",
			CorrectAnswer: "3300",
			Tolerance:     0,
			MonthTag:      "general",
			Active:        true,
		},

		// Criterio 2: ¿Qué se está armando? (build_path)
		{
			Category:      models.TriviaCategoryBuildPath,
			Game:          "wild_rift",
			QuestionText:  "¿Qué se está armando?",
			TargetName:    "Red de armado",
			Clues:         "Brillo + Bacteriófago + Furia",
			Options:       `["Fuerza de la Trinidad", "Cuchilla Oscura", "Guantelete de Hielo", "Calibrador de Sterak"]`,
			CorrectAnswer: "Fuerza de la Trinidad",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryBuildPath,
			Game:          "wild_rift",
			QuestionText:  "¿Qué se está armando?",
			TargetName:    "Red de armado",
			Clues:         "Espadón + Capa de Agilidad + Picacha",
			Options:       `["Filo del Infinito", "Sanguinaria", "Huracán de Runaan", "Cañón de Fuego Rápido"]`,
			CorrectAnswer: "Filo del Infinito",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryBuildPath,
			Game:          "wild_rift",
			QuestionText:  "¿Qué se está armando?",
			TargetName:    "Red de armado",
			Clues:         "Vara Innecesariamente Grande + Vara Innecesariamente Grande",
			Options:       `["Sombrero Mortal de Rabadon", "Bastón del Vacío", "Impulso Cósmico", "Báculo del Arcángel"]`,
			CorrectAnswer: "Sombrero Mortal de Rabadon",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryBuildPath,
			Game:          "wild_rift",
			QuestionText:  "¿Qué se está armando?",
			TargetName:    "Red de armado",
			Clues:         "Bacteriófago + Gemaluz",
			Options:       `["Cuchilla Oscura", "Rostro Espiritual", "Rompecascos", "Placa del Hombre Muerto"]`,
			CorrectAnswer: "Cuchilla Oscura",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryBuildPath,
			Game:          "wild_rift",
			QuestionText:  "¿Qué se está armando?",
			TargetName:    "Red de armado",
			Clues:         "Sable de Aguas Turbias + Arco Curvo",
			Options:       `["Hoja del Rey Arruinado", "Diente de Nashor", "Final del Ingenio", "Filo de la Noche"]`,
			CorrectAnswer: "Hoja del Rey Arruinado",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryBuildPath,
			Game:          "wild_rift",
			QuestionText:  "¿Qué se está armando?",
			TargetName:    "Red de armado",
			Clues:         "Malla del Guardián + Manto Anula-Magia",
			Options:       `["Fuerza de la Naturaleza", "Máscara Abisal", "Presagio de Randuin", "Malla de Espinas"]`,
			CorrectAnswer: "Presagio de Randuin",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryBuildPath,
			Game:          "wild_rift",
			QuestionText:  "¿Qué se está armando?",
			TargetName:    "Red de armado",
			Clues:         "Brillo + Sudario Glacial",
			Options:       `["Guantelete de Hielo", "Perdición del Liche", "Corazón de Hielo", "Gorgona"]`,
			CorrectAnswer: "Guantelete de Hielo",
			MonthTag:      "general",
			Active:        true,
		},

		// Criterio 3: ¿Cuál es el counter de este campeón? (counter)
		{
			Category:      models.TriviaCategoryCounter,
			Game:          "wild_rift",
			QuestionText:  "¿Cuál es el counter de este campeón?",
			TargetName:    "Darius",
			Options:       `["Vayne", "Garen", "Nasus", "Sion"]`,
			CorrectAnswer: "Vayne",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryCounter,
			Game:          "wild_rift",
			QuestionText:  "¿Cuál es el counter de este campeón?",
			TargetName:    "Maestro Yi",
			Options:       `["Rammus", "Kha'Zix", "Evelynn", "Olaf"]`,
			CorrectAnswer: "Rammus",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryCounter,
			Game:          "wild_rift",
			QuestionText:  "¿Cuál es el counter de este campeón?",
			TargetName:    "Zed",
			Options:       `["Lissandra", "Lux", "Veigar", "Ziggs"]`,
			CorrectAnswer: "Lissandra",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryCounter,
			Game:          "wild_rift",
			QuestionText:  "¿Cuál es el counter de este campeón?",
			TargetName:    "Yasuo",
			Options:       `["Renekton", "Ahri", "Lux", "Twisted Fate"]`,
			CorrectAnswer: "Renekton",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryCounter,
			Game:          "wild_rift",
			QuestionText:  "¿Cuál es el counter de este campeón?",
			TargetName:    "Vayne",
			Options:       `["Caitlyn", "Sivir", "Kai'Sa", "Jinx"]`,
			CorrectAnswer: "Caitlyn",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryCounter,
			Game:          "wild_rift",
			QuestionText:  "¿Cuál es el counter de este campeón?",
			TargetName:    "Nasus",
			Options:       `["Teemo", "Kayle", "Kassadin", "Vladimir"]`,
			CorrectAnswer: "Teemo",
			MonthTag:      "general",
			Active:        true,
		},
		{
			Category:      models.TriviaCategoryCounter,
			Game:          "wild_rift",
			QuestionText:  "¿Cuál es el counter de este campeón?",
			TargetName:    "Katarina",
			Options:       `["Galio", "Veigar", "Vel'Koz", "Lux"]`,
			CorrectAnswer: "Galio",
			MonthTag:      "general",
			Active:        true,
		},
	}

	for _, q := range initialQuestions {
		db.Create(&q)
	}
	log.Printf("Seeded %d initial trivia questions successfully.", len(initialQuestions))
}
