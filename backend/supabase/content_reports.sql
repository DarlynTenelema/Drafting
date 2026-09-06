-- content_reports.sql
-- Fase 4: Cola de Moderación de Contenido

CREATE TABLE IF NOT EXISTS public.content_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID NOT NULL REFERENCES public.video_embeds(id) ON DELETE CASCADE,
    reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    reason VARCHAR(255) NOT NULL,
    proof_url VARCHAR(512),
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'rejected')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_content_reports_video_id ON public.content_reports(video_id);
CREATE INDEX IF NOT EXISTS idx_content_reports_reporter_id ON public.content_reports(reporter_id);
