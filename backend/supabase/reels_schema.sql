-- ==============================================================================
-- DRAFTING REELS & TÁCTICOS - ESQUEMA PORTABLE DE BASE DE DATOS (POSTGRESQL)
-- ==============================================================================
-- 100% PostgreSQL estándar: funciona igual en Supabase hoy y en Bare Metal mañana
-- sin depender de auth.uid() ni triggers duplicados con el backend Go.

-- 1. TABLA PRINCIPAL DE REELS (VIDEOS 10-30s, 720p COMPRIMIDOS)
CREATE TABLE IF NOT EXISTS reels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(180) NOT NULL,
    description TEXT DEFAULT '',
    video_url TEXT NOT NULL,
    video_key TEXT DEFAULT '',
    thumbnail_url TEXT DEFAULT '',
    duration_seconds INTEGER DEFAULT 15 CHECK (duration_seconds >= 10 AND duration_seconds <= 30),
    file_size_bytes BIGINT DEFAULT 0,
    width INTEGER DEFAULT 0,
    height INTEGER DEFAULT 0,
    orientation VARCHAR(16) DEFAULT 'portrait', -- 'portrait' o 'landscape'
    game_mode VARCHAR(32) DEFAULT 'wild_rift', -- 'wild_rift' o 'lol_pc'
    category VARCHAR(32) DEFAULT 'jugadas',    -- 'combos', 'micro', 'macro', 'jugadas', 'memes'
    language VARCHAR(10) DEFAULT 'universal',  -- 'es', 'en', 'fr', 'pt', 'universal'
    champion_name VARCHAR(64) DEFAULT '',

    -- Contadores cacheados gestionados atómicamente por el backend Go
    likes_count INTEGER DEFAULT 0 CHECK (likes_count >= 0),
    comments_count INTEGER DEFAULT 0 CHECK (comments_count >= 0),
    saves_count INTEGER DEFAULT 0 CHECK (saves_count >= 0),
    views_count INTEGER DEFAULT 0 CHECK (views_count >= 0),
    verified_views_count INTEGER DEFAULT 0 CHECK (verified_views_count >= 0),
    reports_count INTEGER DEFAULT 0 CHECK (reports_count >= 0),

    -- Algoritmo de viralidad y tendencia (actualizado por worker en lote)
    trend_score NUMERIC DEFAULT 0.0,

    -- Estado y moderación
    active BOOLEAN DEFAULT TRUE,
    silenced_by_reports BOOLEAN DEFAULT FALSE,
    moderation_status VARCHAR(32) DEFAULT 'approved', -- 'pending_scan', 'approved', 'quarantined', 'rejected', 'verified_safe'
    moderation_reason VARCHAR(160) DEFAULT '',
    moderation_score NUMERIC(5,4) DEFAULT 0.0,
    moderation_checked_at TIMESTAMP WITH TIME ZONE,
    content_hash VARCHAR(128) DEFAULT '',
    weighted_reports_score NUMERIC(8,2) DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_reels_feed ON reels(active, language, trend_score DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reels_creator ON reels(creator_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reels_category_mode ON reels(category, game_mode, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reels_reported ON reels(reports_count DESC, silenced_by_reports) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reels_moderation_status ON reels(moderation_status, updated_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reels_content_hash ON reels(content_hash) WHERE content_hash <> '';

-- 2. TABLA DE ME GUSTA (LIKES)
CREATE TABLE IF NOT EXISTS reel_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_reel_user_like UNIQUE (reel_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_reel_likes_user ON reel_likes(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reel_likes_reel ON reel_likes(reel_id);

-- 3. TABLA DE GUARDADOS / FAVORITOS (SAVES)
CREATE TABLE IF NOT EXISTS reel_saves (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_reel_user_save UNIQUE (reel_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_reel_saves_user ON reel_saves(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reel_saves_reel ON reel_saves(reel_id);

-- 4. TABLA DE COMENTARIOS
CREATE TABLE IF NOT EXISTS reel_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content VARCHAR(400) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_reel_comments_reel ON reel_comments(reel_id, created_at ASC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reel_comments_user ON reel_comments(user_id);

-- 5. TABLA DE REGISTRO DE VISTAS ÚNICAS VERIFICADAS (ANTI-BOT)
CREATE TABLE IF NOT EXISTS reel_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    ip_hash VARCHAR(64) DEFAULT '',
    device_id VARCHAR(255) DEFAULT '',
    watched_seconds INTEGER DEFAULT 0,
    watched_percent INTEGER DEFAULT 0,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reel_views_reel_date ON reel_views(reel_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reel_views_reel_ip ON reel_views(reel_id, ip_hash) WHERE ip_hash <> '';
CREATE INDEX IF NOT EXISTS idx_reel_views_reel_device ON reel_views(reel_id, device_id) WHERE device_id <> '';
CREATE UNIQUE INDEX IF NOT EXISTS uq_reel_views_reel_user ON reel_views(reel_id, user_id) WHERE user_id IS NOT NULL;

-- 6. TABLA DE REPORTES COMUNITARIOS (ANTI-BRIGADING PONDERADO)
CREATE TABLE IF NOT EXISTS reel_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason VARCHAR(64) NOT NULL DEFAULT 'other', -- 'nsfw_gore', 'harassment_hate', 'impersonation_stolen', 'spam', 'off_topic', 'other'
    details VARCHAR(300) DEFAULT '',
    weight NUMERIC(4,2) NOT NULL DEFAULT 1.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_reel_user_report UNIQUE (reel_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_reel_reports_reel ON reel_reports(reel_id, created_at DESC);

-- 6B. HASHES PERCEPTUALES DE CONTENIDO PROHIBIDO (+18 / GORE) PARA BLOQUEO A COSTO $0
CREATE TABLE IF NOT EXISTS banned_content_hashes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    frame_hash VARCHAR(64) NOT NULL UNIQUE,
    reason VARCHAR(64) NOT NULL DEFAULT 'nsfw_gore',
    source_reel_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6C. BLOQUEOS ENTRE USUARIOS (REQUISITO PLAY STORE / APP STORE UGC)
CREATE TABLE IF NOT EXISTS user_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_user_block_pair UNIQUE (blocker_id, blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON user_blocks(blocker_id);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON user_blocks(blocked_id);

-- 7. TABLA DE SEGUIDORES (FOLLOWS REALES ENTRE USUARIOS)
CREATE TABLE IF NOT EXISTS user_follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_user_follow_pair UNIQUE (follower_id, following_id)
);

CREATE INDEX IF NOT EXISTS idx_user_follows_following ON user_follows(following_id);
CREATE INDEX IF NOT EXISTS idx_user_follows_follower ON user_follows(follower_id);

-- 8. TABLA DE SOLICITUDES DE RETIRO DE CREADORES (MÍNIMO $100 USD)
CREATE TABLE IF NOT EXISTS creator_payout_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount_usd NUMERIC(12, 4) NOT NULL CHECK (amount_usd >= 100.0),
    verified_views_snapshot BIGINT DEFAULT 0,
    payout_method VARCHAR(32) NOT NULL DEFAULT 'paypal',
    payout_destination VARCHAR(255) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'pending', -- 'pending', 'approved', 'paid', 'rejected'
    admin_notes VARCHAR(300) DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_creator_payouts_user ON creator_payout_requests(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_creator_payouts_status ON creator_payout_requests(status, created_at DESC);

-- 9. EXTENSIONES EN USERS PARA PERFIL DE CREADOR Y BILLETERA HISTÓRICA DE VISTAS
ALTER TABLE users ADD COLUMN IF NOT EXISTS bio VARCHAR(220) DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS twitch_url VARCHAR(255) DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS tiktok_url VARCHAR(255) DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS youtube_url VARCHAR(255) DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS instagram_url VARCHAR(255) DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS kick_url VARCHAR(255) DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS lifetime_verified_views BIGINT DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS moderation_strikes INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS report_trust_score NUMERIC(4,2) DEFAULT 1.0;

-- NOTA: Los triggers previos de likes/saves/comments se eliminan para evitar doble conteo
-- con las transacciones atómicas del backend Go.
DROP TRIGGER IF EXISTS trg_reel_likes_count ON reel_likes;
DROP TRIGGER IF EXISTS trg_reel_saves_count ON reel_saves;
DROP TRIGGER IF EXISTS trg_reel_comments_count ON reel_comments;
