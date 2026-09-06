-- policies.sql
-- NOTA: Este archivo es OPCIONAL y está pensado para el futuro.
-- Actualmente, tu frontend (Flutter) se comunica exclusivamente con la API de Golang.
-- Como la API de Go usa credenciales maestras de Postgres, el RLS no afecta su funcionamiento.
-- Sin embargo, si en el futuro decides que Flutter consulte la base de datos directamente
-- usando la clave anónima de Supabase, deberás ejecutar este script para permitir lectura.

-- 1. Políticas para Usuarios (users)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Permite a un usuario autenticado ver únicamente su propio perfil
CREATE POLICY "Users can view their own profile" 
ON public.users FOR SELECT 
USING (auth.uid() = id);

-- Permite a un usuario autenticado actualizar su propio perfil
CREATE POLICY "Users can update their own profile" 
ON public.users FOR UPDATE 
USING (auth.uid() = id);

-- 2. Políticas para Tickets (tickets)
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;

-- Permite a los usuarios ver los tickets que ellos mismos han creado
CREATE POLICY "Users can view their own tickets"
ON public.tickets FOR SELECT
USING (auth.uid() = user_id);

-- 3. Políticas para Transacciones (payment_transactions)
ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;

-- Permite a los usuarios ver su propio historial de pagos
CREATE POLICY "Users can view their own transactions"
ON public.payment_transactions FOR SELECT
USING (auth.uid() = user_id);

-- 4. Políticas para Límites de Tokens (plan_token_limits y subscription_plans)
-- Estas tablas deberían ser de lectura pública para que cualquier usuario pueda ver los planes
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public can view subscription plans"
ON public.subscription_plans FOR SELECT
USING (true);

ALTER TABLE public.plan_token_limits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public can view plan limits"
ON public.plan_token_limits FOR SELECT
USING (true);

-- IMPORTANTE:
-- Para las inserciones o modificaciones más complejas (ej. pagos, compras),
-- se recomienda que SIEMPRE se hagan desde tu backend en Go para evitar fraudes.
-- Es por eso que no se incluyen políticas de INSERT o DELETE aquí.
