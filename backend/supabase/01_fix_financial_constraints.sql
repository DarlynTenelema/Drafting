-- 01_fix_financial_constraints.sql
-- Ejecuta este script en el SQL Editor de Supabase para parchear tu base de datos actual.
-- ESTO ES UNA BUENA PRÁCTICA (MIGRACIONES): En lugar de borrar las tablas y perder datos,
-- usamos ALTER TABLE para actualizar la estructura en vivo.

-- 1. Arreglar payment_transactions
ALTER TABLE public.payment_transactions
DROP CONSTRAINT IF EXISTS payment_transactions_user_id_fkey;

ALTER TABLE public.payment_transactions
ADD CONSTRAINT payment_transactions_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;

ALTER TABLE public.payment_transactions
ADD CONSTRAINT payment_transactions_amount_check CHECK (amount >= 0);

-- 2. Arreglar suspicious_transactions
ALTER TABLE public.suspicious_transactions
DROP CONSTRAINT IF EXISTS suspicious_transactions_user_id_fkey;

ALTER TABLE public.suspicious_transactions
ADD CONSTRAINT suspicious_transactions_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;

ALTER TABLE public.suspicious_transactions
ADD CONSTRAINT suspicious_transactions_amount_check CHECK (amount >= 0);

-- 3. Arreglar fanarts
ALTER TABLE public.fanarts
ADD CONSTRAINT fanarts_price_essence_check CHECK (price_essence >= 0);

-- 4. Arreglar api_usages
ALTER TABLE public.api_usages
ADD CONSTRAINT api_usages_tokens_used_check CHECK (tokens_used >= 0);
