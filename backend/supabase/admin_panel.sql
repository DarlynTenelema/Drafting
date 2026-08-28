-- admin_panel.sql
-- Fase 1: Añadir roles de usuario y tabla de logs de auditoría

-- 1. Añadir columna 'role' a la tabla users (si no existe)
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS role VARCHAR(50) DEFAULT 'user';

-- Crear índice para búsquedas rápidas por rol
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);

-- Dar permisos de admin a algunos correos de prueba (puedes cambiar esto luego)
-- UPDATE public.users SET role = 'admin' WHERE email = 'tu_correo@gmail.com';

-- 2. Crear tabla de logs de auditoría
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    action VARCHAR(255) NOT NULL, -- ej: 'RESOLVE_TICKET', 'SUSPEND_USER', 'DELETE_VIDEO'
    target_id VARCHAR(255),       -- ID del recurso afectado
    details JSONB,                -- Detalles extra en JSON
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Índice para el panel de administración
CREATE INDEX IF NOT EXISTS idx_audit_logs_admin_id ON public.audit_logs(admin_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);
