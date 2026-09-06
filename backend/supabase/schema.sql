-- Crear la extensión para generar UUIDs aleatorios si no existe
-- Usamos `pgcrypto` y `gen_random_uuid()` para compatibilidad con GORM (gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    google_id VARCHAR(255) UNIQUE,
    email VARCHAR(255) NOT NULL,
    username VARCHAR(255),
    profile_pic VARCHAR(255),
    password_hash VARCHAR(255),
    device_id VARCHAR(255),
    session_token VARCHAR(255),
    stripe_account_id VARCHAR(255),
    stripe_customer_id VARCHAR(255),
    role VARCHAR(50) DEFAULT 'consumer' CHECK (role IN ('consumer', 'entrepreneur', 'admin')),
    strikes INT DEFAULT 0,
    banned BOOLEAN DEFAULT false,
    is_pending_ban BOOLEAN DEFAULT false,
    pending_ban_until TIMESTAMP WITH TIME ZONE,
    has_used_creator_trial BOOLEAN DEFAULT false,
    active_group_id UUID,
    current_goal VARCHAR(255),
    active_plan VARCHAR(50) DEFAULT 'freemium',
    tokens_used_in_cycle INT DEFAULT 0,
    last_token_reset_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_draft_at TIMESTAMP WITH TIME ZONE,
    subscription_ends_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Habilitar Row Level Security (RLS) para proteger los datos
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Crear un índice para búsquedas más rápidas usando google_id
CREATE INDEX idx_users_google_id ON public.users(google_id);

-- Crear un índice para el session_token (útil para el middleware de Auth)
CREATE INDEX idx_users_session_token ON public.users(session_token);

-- Función para actualizar automáticamente la columna updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER 
SET search_path = '' 
AS $$
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

-- Habilitar Row Level Security (RLS)
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;

-- Insertar los planes iniciales
INSERT INTO public.subscription_plans (id, price, duration_hours) VALUES
-- Plus
('sub_plus_1d', 0.24, 24),
('sub_plus_1w', 1.58, 168),
('sub_plus_1m', 5.99, 720),
('sub_plus_1y', 59.99, 8760),
-- Pro
('sub_pro_1d', 0.49, 24),
('sub_pro_1w', 2.99, 168),
('sub_pro_1m', 9.99, 720),
('sub_pro_1y', 99.99, 8760),
-- Ultra
('sub_ultra_1d', 0.99, 24),
('sub_ultra_1w', 5.99, 168),
('sub_ultra_1m', 19.99, 720),
('sub_ultra_1y', 199.99, 8760);

-- Tabla de Transacciones de Pago (Payment Transactions)
CREATE TABLE public.payment_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    plan_id VARCHAR(50) NOT NULL REFERENCES public.subscription_plans(id),
    product_id VARCHAR(100) NOT NULL,
    purchase_token VARCHAR(512) NOT NULL UNIQUE,
    amount DECIMAL(10, 2) NOT NULL CHECK (amount >= 0),
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Habilitar Row Level Security (RLS)
ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;

-- Trigger para ejecutar la función en cada UPDATE de la tabla payment_transactions
CREATE TRIGGER update_payment_transactions_updated_at
BEFORE UPDATE ON public.payment_transactions
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Índice para búsquedas rápidas de transacciones por usuario
CREATE INDEX idx_payment_transactions_user_id ON public.payment_transactions(user_id);

-- Tabla para definir los límites de tokens diarios/totales por plan
CREATE TABLE public.plan_token_limits (
    plan_id VARCHAR(50) PRIMARY KEY, -- 'sub_plus_1d', 'sub_ultra_1m', etc.
    token_limit INT NOT NULL,
    reset_period VARCHAR(20) NOT NULL, -- 'daily', 'weekly', 'monthly', 'yearly', 'none'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Habilitar Row Level Security (RLS)
ALTER TABLE public.plan_token_limits ENABLE ROW LEVEL SECURITY;

-- Insertar los límites según el plan de negocios
INSERT INTO public.plan_token_limits (plan_id, token_limit, reset_period) VALUES
-- Ultra
('sub_ultra_1d', 250000, 'none'),      -- 250K por 24h
('sub_ultra_1w', 300000, 'daily'),     -- 300K diarios por una semana
('sub_ultra_1m', 2500000, 'weekly'),   -- 2.5M semanales por un mes
('sub_ultra_1y', 12000000, 'monthly'); -- 12M mensuales por un año

-- (Plus y Pro no incluyen tokens para chat coach explícitos en el documento, 
-- pero se pueden configurar aquí si se desea habilitar con un límite menor)

-- Los tokens_used_in_cycle y last_token_reset_date ahora están en el CREATE TABLE principal.
