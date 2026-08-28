-- suggestions.sql
-- Fase 3: Recomendaciones y Sugerencias

CREATE TABLE IF NOT EXISTS public.suggestions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    category VARCHAR(50) NOT NULL DEFAULT 'other', -- 'ui', 'economy', 'content', 'features', 'other'
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'new', -- 'new', 'under_review', 'implemented', 'rejected'
    upvotes INT DEFAULT 0, -- Opcional, por si los usuarios pueden votar sugerencias en el futuro
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_suggestions_status ON public.suggestions(status);
CREATE INDEX IF NOT EXISTS idx_suggestions_category ON public.suggestions(category);

-- Trigger para updated_at (asume que la función update_updated_at_column() ya existe en schema.sql)
DROP TRIGGER IF EXISTS update_suggestions_updated_at ON public.suggestions;
CREATE TRIGGER update_suggestions_updated_at
BEFORE UPDATE ON public.suggestions
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
