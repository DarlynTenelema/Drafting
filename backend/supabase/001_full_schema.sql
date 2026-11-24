-- ==============================================================================
-- DRAFTING - ESQUEMA COMPLETO PORTABLE DE BASE DE DATOS (POSTGRESQL)
-- ==============================================================================
-- 100% seguro para ejecutar sobre una base de datos YA EN PRODUCCIÓN:
--   * Solo usa CREATE TABLE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS / CREATE INDEX IF NOT EXISTS.
--   * Nunca ejecuta DROP, TRUNCATE ni DELETE sobre usuarios o compras.
--   * Las llaves foráneas (FK) y restricciones CHECK se agregan con NOT VALID para
--     proteger todas las escrituras nuevas sin fallar ni rechazar filas históricas.
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------------------------
-- 1. USUARIOS Y BILLETERAS DE CONSULTAS (CLASSIC, FLAKE 1.0, AUREON 1.0)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    google_id VARCHAR(255) UNIQUE,
    email VARCHAR(255) NOT NULL,
    username VARCHAR(255) DEFAULT '',
    profile_pic VARCHAR(255) DEFAULT '',
    password_hash VARCHAR(255) DEFAULT '',
    device_id VARCHAR(255) DEFAULT '',
    session_token VARCHAR(255) DEFAULT '',
    role VARCHAR(50) DEFAULT 'consumer',
    banned BOOLEAN DEFAULT FALSE,
    active_plan VARCHAR(50) DEFAULT 'freemium',

    -- Contadores agregados / legacy sincronizados con billeteras V2
    available_queries INTEGER DEFAULT 3,
    bonus_queries INTEGER DEFAULT 0,
    daily_queries INTEGER DEFAULT 3,
    ad_queries INTEGER DEFAULT 0,
    purchased_queries INTEGER DEFAULT 0,
    subscription_queries INTEGER DEFAULT 0,
    gift_queries INTEGER DEFAULT 0,
    trivia_lives INTEGER DEFAULT 5,

    -- Billeteras independientes por modelo de IA (V2)
    classic_daily INTEGER DEFAULT 3,
    classic_ad INTEGER DEFAULT 0,
    classic_purchased INTEGER DEFAULT 0,
    classic_last_recharge_at TIMESTAMPTZ,

    flake_ad INTEGER DEFAULT 0,
    flake_purchased INTEGER DEFAULT 0,
    flake_ads_today INTEGER DEFAULT 0,
    flake_last_ad_date VARCHAR(10) DEFAULT '',

    aureon_ad INTEGER DEFAULT 0,
    aureon_purchased INTEGER DEFAULT 0,
    aureon_ads_today INTEGER DEFAULT 0,
    aureon_last_ad_date VARCHAR(10) DEFAULT '',

    models_v2_migrated BOOLEAN DEFAULT FALSE,

    -- Suscripción y límites diarios de transferencias
    subscription_plan VARCHAR(50) DEFAULT 'none',
    subscription_ends_at TIMESTAMPTZ,
    has_purchased_starter BOOLEAN DEFAULT FALSE,
    daily_transferred_today INTEGER DEFAULT 0,
    last_transfer_date VARCHAR(10) DEFAULT '',
    daily_received_today INTEGER DEFAULT 0,
    last_received_date VARCHAR(10) DEFAULT '',

    -- Referidos y afiliados
    last_daily_reward_date VARCHAR(10) DEFAULT '',
    referral_code VARCHAR(16) DEFAULT '',
    referred_by_id UUID,
    referred_by_streamer_code VARCHAR(32) DEFAULT '',
    referral_count INTEGER DEFAULT 0,
    referral_rewards_claimed INTEGER DEFAULT 0,

    last_draft_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_users_email_lower ON users (LOWER(email)) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_referral_code ON users (UPPER(referral_code)) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_referred_by_id ON users (referred_by_id) WHERE referred_by_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_referred_by_streamer ON users (referred_by_streamer_code) WHERE referred_by_streamer_code <> '';
CREATE INDEX IF NOT EXISTS idx_users_device_banned ON users (device_id) WHERE banned = TRUE AND device_id <> '';
CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users (deleted_at);

-- Restricciones CHECK no destructivas (NOT VALID: valida todas las escrituras nuevas sin romper datos históricos)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_non_negative_wallets') THEN
        ALTER TABLE users ADD CONSTRAINT chk_users_non_negative_wallets CHECK (
            classic_daily >= 0 AND classic_ad >= 0 AND classic_purchased >= 0 AND
            flake_ad >= 0 AND flake_purchased >= 0 AND
            aureon_ad >= 0 AND aureon_purchased >= 0 AND
            gift_queries >= 0 AND trivia_lives >= 0
        ) NOT VALID;
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 2. USO DE API DE IA (AUDITORÍA DE TOKENS)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS api_usages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    tokens_used INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_api_usages_user_created ON api_usages (user_id, created_at DESC);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_api_usages_user') THEN
        ALTER TABLE api_usages
            ADD CONSTRAINT fk_api_usages_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE NOT VALID;
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 3. TRANSACCIONES DE TIENDA, SUSCRIPCIONES Y DONACIONES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    type VARCHAR(50) NOT NULL DEFAULT 'pack',
    item_key VARCHAR(50) NOT NULL DEFAULT '',
    amount_usd DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    queries_added INTEGER NOT NULL DEFAULT 0,
    provider VARCHAR(50) DEFAULT 'google_play',
    provider_transaction_id VARCHAR(255),
    purchase_token TEXT DEFAULT '',
    status VARCHAR(50) DEFAULT 'completed',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_transactions_user_created ON transactions (user_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_transactions_provider_tx_id ON transactions (provider_transaction_id);
CREATE INDEX IF NOT EXISTS idx_transactions_purchase_token ON transactions (purchase_token) WHERE purchase_token <> '';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_transactions_user') THEN
        ALTER TABLE transactions
            ADD CONSTRAINT fk_transactions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_transactions_amount_non_negative') THEN
        ALTER TABLE transactions
            ADD CONSTRAINT chk_transactions_amount_non_negative CHECK (amount_usd >= 0 AND queries_added >= 0) NOT VALID;
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 4. TRANSFERENCIAS DE CONSULTAS ENTRE JUGADORES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS query_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_user_id UUID NOT NULL,
    from_referral_code VARCHAR(16) DEFAULT '',
    to_user_id UUID NOT NULL,
    to_referral_code VARCHAR(16) DEFAULT '',
    amount INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_query_transfers_sender ON query_transfers (from_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_query_transfers_receiver ON query_transfers (to_user_id, created_at DESC);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_query_transfers_from_user') THEN
        ALTER TABLE query_transfers
            ADD CONSTRAINT fk_query_transfers_from_user FOREIGN KEY (from_user_id) REFERENCES users(id) ON DELETE RESTRICT NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_query_transfers_to_user') THEN
        ALTER TABLE query_transfers
            ADD CONSTRAINT fk_query_transfers_to_user FOREIGN KEY (to_user_id) REFERENCES users(id) ON DELETE RESTRICT NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_query_transfers_amount_positive') THEN
        ALTER TABLE query_transfers
            ADD CONSTRAINT chk_query_transfers_amount_positive CHECK (amount > 0 AND amount <= 10) NOT VALID;
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 5. ECOSISTEMA: STREAMERS, COMISIONES, PATROCINADORES, TORNEO C.L.A, COMUNIDAD
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS streamer_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(120) NOT NULL,
    email VARCHAR(255) NOT NULL,
    platform VARCHAR(50) NOT NULL,
    channel_url VARCHAR(500) NOT NULL,
    followers_count INTEGER DEFAULT 0,
    promo_code VARCHAR(32) NOT NULL UNIQUE,
    wants_caster BOOLEAN DEFAULT FALSE,
    payment_method VARCHAR(100) DEFAULT 'paypal',
    payment_details VARCHAR(255) DEFAULT '',
    status VARCHAR(32) DEFAULT 'approved',
    commission_rate DECIMAL(5,2) DEFAULT 0.25,
    total_referrals INTEGER DEFAULT 0,
    total_sales_count INTEGER DEFAULT 0,
    total_earnings_usd DECIMAL(10,2) DEFAULT 0.00,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_streamer_applications_email ON streamer_applications (LOWER(email));
CREATE INDEX IF NOT EXISTS idx_streamer_applications_status ON streamer_applications (status, total_referrals DESC);

CREATE TABLE IF NOT EXISTS streamer_commissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    streamer_id UUID NOT NULL,
    promo_code VARCHAR(32) NOT NULL,
    buyer_user_id UUID NOT NULL,
    transaction_id UUID NOT NULL,
    item_key VARCHAR(50) NOT NULL,
    sale_amount_usd DECIMAL(10,2) NOT NULL,
    commission_usd DECIMAL(10,2) NOT NULL,
    status VARCHAR(32) DEFAULT 'credited',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_streamer_commissions_streamer ON streamer_commissions (streamer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_streamer_commissions_tx ON streamer_commissions (transaction_id);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_streamer_commissions_streamer') THEN
        ALTER TABLE streamer_commissions
            ADD CONSTRAINT fk_streamer_commissions_streamer FOREIGN KEY (streamer_id) REFERENCES streamer_applications(id) ON DELETE RESTRICT NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_streamer_commissions_buyer') THEN
        ALTER TABLE streamer_commissions
            ADD CONSTRAINT fk_streamer_commissions_buyer FOREIGN KEY (buyer_user_id) REFERENCES users(id) ON DELETE RESTRICT NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_streamer_commissions_tx') THEN
        ALTER TABLE streamer_commissions
            ADD CONSTRAINT fk_streamer_commissions_tx FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE RESTRICT NOT VALID;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS sponsor_inquiries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    brand_name VARCHAR(150) NOT NULL,
    contact_name VARCHAR(120) NOT NULL,
    contact_email VARCHAR(255) NOT NULL,
    whatsapp_or_discord VARCHAR(120) NOT NULL,
    plan_type VARCHAR(64) NOT NULL,
    modality VARCHAR(50) DEFAULT 'paid',
    budget_usd DECIMAL(10,2) DEFAULT 0.00,
    target_url VARCHAR(500) DEFAULT '',
    message TEXT DEFAULT '',
    status VARCHAR(32) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS tournament_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    registration_type VARCHAR(32) NOT NULL DEFAULT 'team',
    team_name VARCHAR(120) NOT NULL,
    team_tag VARCHAR(16) DEFAULT '',
    captain_name VARCHAR(120) NOT NULL,
    contact_discord VARCHAR(120) NOT NULL,
    contact_whatsapp VARCHAR(120) DEFAULT '',
    average_rank VARCHAR(64) DEFAULT 'Diamante',
    server_region VARCHAR(64) DEFAULT 'LAN / LAS',
    roster_notes TEXT DEFAULT '',
    drafting_code VARCHAR(32) DEFAULT '',
    status VARCHAR(32) DEFAULT 'registered',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_tournament_reg_type_date ON tournament_registrations (registration_type, created_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS community_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_key VARCHAR(64) NOT NULL,
    voter_identifier VARCHAR(255) NOT NULL,
    suggestion_text TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_community_votes_feature ON community_votes (feature_key);
CREATE INDEX IF NOT EXISTS idx_community_votes_voter ON community_votes (voter_identifier);

CREATE TABLE IF NOT EXISTS newsletter_subscribers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    player_code VARCHAR(32) DEFAULT '',
    favorite_role VARCHAR(50) DEFAULT 'Mid',
    source VARCHAR(50) DEFAULT 'web',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS featured_promotions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(120) NOT NULL,
    subtitle VARCHAR(255) NOT NULL,
    platform VARCHAR(50) NOT NULL,
    stream_url VARCHAR(500) NOT NULL,
    avatar_url VARCHAR(500) DEFAULT '',
    badge_text VARCHAR(64) DEFAULT 'STREAMER DESTACADO',
    promo_code VARCHAR(32) DEFAULT '',
    is_live BOOLEAN DEFAULT TRUE,
    active BOOLEAN DEFAULT TRUE,
    priority INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_featured_promotions_active ON featured_promotions (active, priority DESC, created_at DESC);

-- ------------------------------------------------------------------------------
-- 6. EVENTOS, REDES SOCIALES, CONFIGURACIÓN DE VERSIÓN Y DONADORES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(160) NOT NULL,
    subtitle VARCHAR(500) NOT NULL,
    title_pt VARCHAR(160) DEFAULT '',
    subtitle_pt VARCHAR(500) DEFAULT '',
    title_en VARCHAR(160) DEFAULT '',
    subtitle_en VARCHAR(500) DEFAULT '',
    title_fr VARCHAR(160) DEFAULT '',
    subtitle_fr VARCHAR(500) DEFAULT '',
    platform VARCHAR(50) NOT NULL DEFAULT 'tiktok',
    event_type VARCHAR(40) NOT NULL DEFAULT 'event',
    action_url VARCHAR(500) NOT NULL,
    badge_text VARCHAR(64) DEFAULT 'EVENTO OFICIAL',
    event_date_text VARCHAR(80) DEFAULT '',
    is_live BOOLEAN DEFAULT FALSE,
    active BOOLEAN DEFAULT TRUE,
    priority INTEGER DEFAULT 5,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_app_events_active ON app_events (active, is_live DESC, priority DESC, updated_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS social_link_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    platform VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(80) NOT NULL,
    handle VARCHAR(100) DEFAULT '',
    url VARCHAR(500) NOT NULL,
    description VARCHAR(255) DEFAULT '',
    active BOOLEAN DEFAULT TRUE,
    sort_order INTEGER DEFAULT 1,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app_version_configs (
    id VARCHAR(32) PRIMARY KEY,
    latest_version_code INTEGER NOT NULL DEFAULT 38,
    latest_version_name VARCHAR(32) NOT NULL DEFAULT '1.0.6',
    min_required_version_code INTEGER NOT NULL DEFAULT 37,
    force_update BOOLEAN DEFAULT FALSE,
    update_mode VARCHAR(20) DEFAULT 'flexible',
    release_notes_es TEXT DEFAULT '',
    release_notes_pt TEXT DEFAULT '',
    release_notes_en TEXT DEFAULT '',
    release_notes_fr TEXT DEFAULT '',
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS donor_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE,
    display_name VARCHAR(120) NOT NULL,
    avatar_url VARCHAR(500) DEFAULT '',
    platform VARCHAR(40) DEFAULT 'tiktok',
    channel_handle VARCHAR(100) DEFAULT '',
    channel_url VARCHAR(500) DEFAULT '',
    bio_message VARCHAR(240) DEFAULT '',
    is_live BOOLEAN DEFAULT FALSE,
    total_donated_usd DECIMAL(10,2) DEFAULT 0.00,
    donations_count INTEGER DEFAULT 0,
    last_donated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_donor_profiles_ranking ON donor_profiles (total_donated_usd DESC, is_live DESC, last_donated_at DESC) WHERE deleted_at IS NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_donor_profiles_user') THEN
        ALTER TABLE donor_profiles
            ADD CONSTRAINT fk_donor_profiles_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE NOT VALID;
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 7. TRIVIA
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS trivia_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category VARCHAR(32) NOT NULL,
    game VARCHAR(32) DEFAULT 'wild_rift',
    question_text TEXT NOT NULL,
    target_name VARCHAR(128) NOT NULL,
    clues TEXT DEFAULT '',
    options TEXT DEFAULT '[]',
    correct_answer TEXT NOT NULL,
    tolerance INTEGER DEFAULT 0,
    month_tag VARCHAR(32) DEFAULT 'general',
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_trivia_questions_cat_act ON trivia_questions (category, active) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_trivia_questions_month ON trivia_questions (month_tag);

CREATE TABLE IF NOT EXISTS trivia_user_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    question_id UUID NOT NULL,
    category VARCHAR(32) NOT NULL,
    is_correct BOOLEAN DEFAULT FALSE,
    attempts_count INTEGER DEFAULT 1,
    last_attempt_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trivia_user_progress_user ON trivia_user_progress (user_id, category);
CREATE UNIQUE INDEX IF NOT EXISTS idx_trivia_user_question ON trivia_user_progress (user_id, question_id);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_trivia_progress_user') THEN
        ALTER TABLE trivia_user_progress
            ADD CONSTRAINT fk_trivia_progress_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE NOT VALID;
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 8. REELS TÁCTICOS (COMPLEMENTA reels_schema.sql CON FKS NOT VALID)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL,
    title VARCHAR(180) NOT NULL,
    description TEXT DEFAULT '',
    video_url TEXT NOT NULL,
    video_key TEXT DEFAULT '',
    thumbnail_url TEXT DEFAULT '',
    duration_seconds INTEGER DEFAULT 15,
    file_size_bytes BIGINT DEFAULT 0,
    game_mode VARCHAR(32) DEFAULT 'wild_rift',
    category VARCHAR(32) DEFAULT 'jugadas',
    language VARCHAR(10) DEFAULT 'universal',
    champion_name VARCHAR(64) DEFAULT '',
    likes_count INTEGER DEFAULT 0,
    comments_count INTEGER DEFAULT 0,
    saves_count INTEGER DEFAULT 0,
    views_count INTEGER DEFAULT 0,
    verified_views_count INTEGER DEFAULT 0,
    reports_count INTEGER DEFAULT 0,
    trend_score NUMERIC DEFAULT 0.0,
    active BOOLEAN DEFAULT TRUE,
    silenced_by_reports BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_reels_feed ON reels (active, language, trend_score DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reels_creator ON reels (creator_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reels_category_mode ON reels (category, game_mode, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reels_reported ON reels (reports_count DESC, silenced_by_reports) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS reel_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_reel_user_like ON reel_likes (reel_id, user_id);
CREATE INDEX IF NOT EXISTS idx_reel_likes_user ON reel_likes (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS reel_saves (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_reel_user_save ON reel_saves (reel_id, user_id);
CREATE INDEX IF NOT EXISTS idx_reel_saves_user ON reel_saves (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS reel_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL,
    user_id UUID NOT NULL,
    content VARCHAR(400) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_reel_comments_reel ON reel_comments (reel_id, created_at ASC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reel_comments_user ON reel_comments (user_id);

CREATE TABLE IF NOT EXISTS reel_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL,
    user_id UUID,
    ip_hash VARCHAR(64) DEFAULT '',
    watched_seconds INTEGER DEFAULT 0,
    watched_percent INTEGER DEFAULT 0,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_reel_views_reel_date ON reel_views (reel_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_reel_views_reel_user ON reel_views (reel_id, user_id) WHERE user_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS reel_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL,
    user_id UUID NOT NULL,
    reason VARCHAR(64) NOT NULL DEFAULT 'other',
    details VARCHAR(300) DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_reel_user_report ON reel_reports (reel_id, user_id);
CREATE INDEX IF NOT EXISTS idx_reel_reports_reel ON reel_reports (reel_id, created_at DESC);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_reels_creator') THEN
        ALTER TABLE reels ADD CONSTRAINT fk_reels_creator FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE CASCADE NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_reel_likes_reel') THEN
        ALTER TABLE reel_likes ADD CONSTRAINT fk_reel_likes_reel FOREIGN KEY (reel_id) REFERENCES reels(id) ON DELETE CASCADE NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_reel_likes_user') THEN
        ALTER TABLE reel_likes ADD CONSTRAINT fk_reel_likes_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_reel_saves_reel') THEN
        ALTER TABLE reel_saves ADD CONSTRAINT fk_reel_saves_reel FOREIGN KEY (reel_id) REFERENCES reels(id) ON DELETE CASCADE NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_reel_saves_user') THEN
        ALTER TABLE reel_saves ADD CONSTRAINT fk_reel_saves_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_reel_comments_reel') THEN
        ALTER TABLE reel_comments ADD CONSTRAINT fk_reel_comments_reel FOREIGN KEY (reel_id) REFERENCES reels(id) ON DELETE CASCADE NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_reel_comments_user') THEN
        ALTER TABLE reel_comments ADD CONSTRAINT fk_reel_comments_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_reel_views_reel') THEN
        ALTER TABLE reel_views ADD CONSTRAINT fk_reel_views_reel FOREIGN KEY (reel_id) REFERENCES reels(id) ON DELETE CASCADE NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_reel_views_user') THEN
        ALTER TABLE reel_views ADD CONSTRAINT fk_reel_views_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_reel_reports_reel') THEN
        ALTER TABLE reel_reports ADD CONSTRAINT fk_reel_reports_reel FOREIGN KEY (reel_id) REFERENCES reels(id) ON DELETE CASCADE NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_reel_reports_user') THEN
        ALTER TABLE reel_reports ADD CONSTRAINT fk_reel_reports_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE NOT VALID;
    END IF;
END $$;

-- ==============================================================================
-- OPCIONAL (SOLO SI SIGUES ALOJANDO POSTGRES EN SUPABASE):
-- Bloquea acceso directo desde la anon/authenticated key de PostgREST, ya que
-- el backend en Go se conecta con el rol propietario/service_role.
-- Descomenta y ejecuta este bloque en el SQL Editor de Supabase si aplica:
-- ==============================================================================
-- DO $$
-- DECLARE tbl TEXT;
-- BEGIN
--     FOR tbl IN
--         SELECT tablename FROM pg_tables WHERE schemaname = 'public'
--     LOOP
--         EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl);
--     END LOOP;
-- END $$;
