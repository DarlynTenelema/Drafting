-- Crear la extensión para generar UUIDs aleatorios si no existe
-- Usamos `pgcrypto` y `gen_random_uuid()` para compatibilidad con GORM (gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    google_id VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255) NOT NULL,
    session_token VARCHAR(255),
    last_draft_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    subscription_ends_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Crear un índice para búsquedas más rápidas usando google_id
CREATE INDEX idx_users_google_id ON public.users(google_id);

-- Crear un índice para el session_token (útil para el middleware de Auth)
CREATE INDEX idx_users_session_token ON public.users(session_token);

-- Función para actualizar automáticamente la columna updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger para ejecutar la función en cada UPDATE de la tabla users
CREATE TRIGGER update_users_updated_at
BEFORE UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Tabla de Planes de Suscripción (Subscription Plans)
CREATE TABLE public.subscription_plans (
    id VARCHAR(50) PRIMARY KEY, -- ej: 'micro_24h', 'medium_30d', 'max_365d'
    price DECIMAL(10, 2) NOT NULL,
    duration_hours INT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insertar los planes iniciales
INSERT INTO public.subscription_plans (id, price, duration_hours) VALUES
('micro_24h', 0.49, 24),
('micro_72h', 1.47, 72),
('micro_120h', 2.45, 120),
('medium_30d', 9.99, 720),
('medium_90d', 29.97, 2160),
('medium_150d', 49.95, 3600),
('max_180d', 49.99, 4320),
('max_240d', 79.99, 5760),
('max_365d', 99.99, 8760);

-- Tabla de Transacciones de Pago (Payment Transactions)
CREATE TABLE public.payment_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    plan_id VARCHAR(50) NOT NULL REFERENCES public.subscription_plans(id),
    product_id VARCHAR(100) NOT NULL,
    purchase_token VARCHAR(512) NOT NULL UNIQUE,
    amount DECIMAL(10, 2) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Trigger para ejecutar la función en cada UPDATE de la tabla payment_transactions
CREATE TRIGGER update_payment_transactions_updated_at
BEFORE UPDATE ON public.payment_transactions
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Índice para búsquedas rápidas de transacciones por usuario
CREATE INDEX idx_payment_transactions_user_id ON public.payment_transactions(user_id);
