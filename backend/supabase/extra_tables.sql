CREATE TABLE IF NOT EXISTS public.match_screenshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_session_id UUID NOT NULL REFERENCES public.match_sessions(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    scene_type VARCHAR(50) CHECK (scene_type IN ('draft', 'in_game')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_match_screenshots_session_id ON public.match_screenshots(match_session_id);

CREATE TABLE IF NOT EXISTS public.match_chat_threads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_session_id UUID NOT NULL REFERENCES public.match_sessions(id) ON DELETE CASCADE,
    title VARCHAR(100) DEFAULT 'Nuevo Chat',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_match_chat_threads_session_id ON public.match_chat_threads(match_session_id);

CREATE TABLE IF NOT EXISTS public.match_chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID NOT NULL REFERENCES public.match_chat_threads(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL CHECK (role IN ('user', 'model')),
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_match_chat_messages_thread_id ON public.match_chat_messages(thread_id);

-- 5. Modulo: Resto de Moderacion (moderation.go) (sin contar content_reports que se reescribio)
CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL CHECK (type IN ('bug', 'inappropriate_content', 'price_adjustment')),
    description TEXT NOT NULL,
    image_url VARCHAR(512),
    related_entity_id UUID,
    status VARCHAR(50) DEFAULT 'open' CHECK (status IN ('open', 'reviewed', 'resolved', 'rejected')),
    admin_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_reports_reporter_id ON public.reports(reporter_id);

CREATE TABLE IF NOT EXISTS public.identity_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id UUID NOT NULL REFERENCES public.channels(id) ON DELETE CASCADE,
    proof_url VARCHAR(512) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_identity_verifications_channel_id ON public.identity_verifications(channel_id);

-- 6. Modulo: Interactions (interactions.go)
CREATE TABLE IF NOT EXISTS public.comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID NOT NULL,
    content_type VARCHAR(50) NOT NULL DEFAULT 'video',
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    parent_id UUID,
    content TEXT NOT NULL,
    likes INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_comments_content ON public.comments(content_id, content_type);

CREATE TABLE IF NOT EXISTS public.video_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID NOT NULL REFERENCES public.video_embeds(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(video_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscriber_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    channel_id UUID NOT NULL REFERENCES public.channels(id) ON DELETE CASCADE,
    notifications_enabled BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(subscriber_id, channel_id)
);

CREATE TABLE IF NOT EXISTS public.fanart_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fanart_id UUID NOT NULL REFERENCES public.fanarts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(fanart_id, user_id)
);

-- 7. Modulo: Creator Profile (creator_profile.go)
CREATE TABLE IF NOT EXISTS public.creator_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    artist_name VARCHAR(255) UNIQUE NOT NULL,
    tags VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
