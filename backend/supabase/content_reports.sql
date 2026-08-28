-- content_reports.sql
-- Fase 4: Cola de Moderación de Contenido

CREATE TABLE IF NOT EXISTS public.content_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    content_id UUID NOT NULL, -- UUID del VideoEmbed o Fanart
    content_type VARCHAR(50) NOT NULL, -- 'video', 'fanart', 'channel'
    reason VARCHAR(50) NOT NULL, -- 'nsfw', 'copyright', 'spam', 'harassment', 'other'
    details TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'pending', -- 'pending', 'resolved_deleted', 'resolved_kept'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_content_reports_content_id ON public.content_reports(content_id);
CREATE INDEX IF NOT EXISTS idx_content_reports_status ON public.content_reports(status);
