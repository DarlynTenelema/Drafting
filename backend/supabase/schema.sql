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
('plus_1d', 0.24, 24),
('plus_1w', 1.58, 168),
('plus_1m', 5.99, 720),
('plus_1y', 59.99, 8760),
-- Pro
('pro_1d', 0.49, 24),
('pro_1w', 2.99, 168),
('pro_1m', 9.99, 720),
('pro_1y', 99.99, 8760),
-- Ultra
('ultra_1d', 0.99, 24),
('ultra_1w', 5.99, 168),
('ultra_1m', 19.99, 720),
('ultra_1y', 199.99, 8760);

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

-- Habilitar Row Level Security (RLS)
ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;

-- Trigger para ejecutar la función en cada UPDATE de la tabla payment_transactions
CREATE TRIGGER update_payment_transactions_updated_at
BEFORE UPDATE ON public.payment_transactions
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Índice para búsquedas rápidas de transacciones por usuario
CREATE INDEX idx_payment_transactions_user_id ON public.payment_transactions(user_id);

-- Tabla para definir los límites de tokens diarios por plan
CREATE TABLE public.plan_token_limits (
    plan_tier VARCHAR(50) PRIMARY KEY, -- 'plus', 'pro', 'ultra'
    daily_token_limit INT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Habilitar Row Level Security (RLS)
ALTER TABLE public.plan_token_limits ENABLE ROW LEVEL SECURITY;

-- Insertar los límites diarios (sin freemium)
INSERT INTO public.plan_token_limits (plan_tier, daily_token_limit) VALUES
('plus', 100000),      
('pro', 500000),       
('ultra', 2000000);    

-- Modificar la tabla 'users' para llevar el conteo de consumo diario
ALTER TABLE public.users
ADD COLUMN daily_tokens_used INT DEFAULT 0,
ADD COLUMN last_token_reset_date DATE DEFAULT CURRENT_DATE;
