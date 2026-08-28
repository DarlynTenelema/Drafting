-- tickets.sql
-- Fase 2: Gestión de Reportes y Atención al Cliente

-- 1. Crear tabla de Tickets
CREATE TABLE IF NOT EXISTS public.tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    subject VARCHAR(255) NOT NULL,
    ticket_type VARCHAR(50) NOT NULL, -- 'bug', 'fraud', 'support', 'other'
    status VARCHAR(50) NOT NULL DEFAULT 'open', -- 'open', 'in_progress', 'resolved', 'closed'
    priority VARCHAR(50) NOT NULL DEFAULT 'medium', -- 'low', 'medium', 'high', 'urgent'
    assigned_admin_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Índices para búsqueda rápida en el panel
CREATE INDEX IF NOT EXISTS idx_tickets_user_id ON public.tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON public.tickets(status);
CREATE INDEX IF NOT EXISTS idx_tickets_type ON public.tickets(ticket_type);

-- Trigger para updated_at (asume que la función update_updated_at_column() ya existe en schema.sql)
DROP TRIGGER IF EXISTS update_tickets_updated_at ON public.tickets;
CREATE TRIGGER update_tickets_updated_at
BEFORE UPDATE ON public.tickets
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- 2. Crear tabla de Mensajes de Tickets
CREATE TABLE IF NOT EXISTS public.ticket_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES public.tickets(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    is_internal_note BOOLEAN DEFAULT false, -- Para que los admins dejen notas privadas
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ticket_messages_ticket_id ON public.ticket_messages(ticket_id);
