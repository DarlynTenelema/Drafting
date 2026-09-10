-- script_cascade_delete_users.sql
-- Ejecuta este script en el SQL Editor de Supabase.
-- Este script reemplaza las restricciones (RESTRICT) por CASCADE en las tablas financieras
-- y otras tablas que dependen de 'users', para que al borrar un usuario desde el Table Editor
-- se borre todo su rastro automáticamente.

-- ADVERTENCIA: Borrar usuarios con historial financiero en producción generalmente no es recomendado.
-- Se usa CASCADE bajo tu propio riesgo (ideal para entornos de desarrollo/pruebas).

BEGIN;

-- 1. Modificar payment_transactions (estaba en RESTRICT)
ALTER TABLE public.payment_transactions
DROP CONSTRAINT IF EXISTS payment_transactions_user_id_fkey;

ALTER TABLE public.payment_transactions
ADD CONSTRAINT payment_transactions_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- 2. Modificar suspicious_transactions (estaba en RESTRICT)
ALTER TABLE public.suspicious_transactions
DROP CONSTRAINT IF EXISTS suspicious_transactions_user_id_fkey;

ALTER TABLE public.suspicious_transactions
ADD CONSTRAINT suspicious_transactions_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- 3. Modificar groups (si usaste GORM AutoMigrate, la constraint suele llamarse fk_groups_owner)
-- (Omitir si no existe, por eso usamos IF EXISTS cuando sea posible, 
-- pero PostgreSQL requiere saber el nombre exacto de la llave foránea)
-- Si GORM la creó, suele llamarse fk_groups_owner o fk_users_group
DO $$
DECLARE
    fk_name text;
BEGIN
    -- Busca la FK de la tabla groups que apunta a users
    SELECT constraint_name INTO fk_name
    FROM information_schema.table_constraints
    WHERE table_name = 'groups' AND constraint_type = 'FOREIGN KEY';
    
    IF fk_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE public.groups DROP CONSTRAINT ' || fk_name;
        EXECUTE 'ALTER TABLE public.groups ADD CONSTRAINT ' || fk_name || ' FOREIGN KEY (owner_id) REFERENCES public.users(id) ON DELETE CASCADE';
    END IF;
END $$;

-- 4. Modificar wallets (GORM AutoMigrate)
DO $$
DECLARE
    fk_name text;
BEGIN
    SELECT constraint_name INTO fk_name
    FROM information_schema.table_constraints
    WHERE table_name = 'wallets' AND constraint_type = 'FOREIGN KEY';
    
    IF fk_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE public.wallets DROP CONSTRAINT ' || fk_name;
        EXECUTE 'ALTER TABLE public.wallets ADD CONSTRAINT ' || fk_name || ' FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE';
    END IF;
END $$;

-- 5. Modificar transactions (Historial del wallet)
DO $$
DECLARE
    fk_name text;
BEGIN
    SELECT constraint_name INTO fk_name
    FROM information_schema.table_constraints
    WHERE table_name = 'transactions' AND constraint_type = 'FOREIGN KEY';
    
    IF fk_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE public.transactions DROP CONSTRAINT ' || fk_name;
        EXECUTE 'ALTER TABLE public.transactions ADD CONSTRAINT ' || fk_name || ' FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE';
    END IF;
END $$;

COMMIT;

CREATE TABLE IF NOT EXISTS public.group_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted')),
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_group_invitations_group_id ON public.group_invitations(group_id);

-- 1. Eliminar primero los productos huérfanos actuales para que la restricción pueda aplicarse
DELETE FROM public.groups
WHERE owner_id NOT IN (SELECT id FROM public.users);

DELETE FROM public.otp_profiles
WHERE owner_id NOT IN (SELECT id FROM public.users);

-- 2. Eliminar restricciones antiguas si existen (Omitirá error si no existen gracias a 'IF EXISTS')
DO $$
BEGIN
    -- Intentar eliminar la clave foránea por defecto que GORM pudo haber creado (generalmente fk_groups_user u owner)
    BEGIN
        ALTER TABLE public.groups DROP CONSTRAINT fk_groups_owner;
    EXCEPTION WHEN undefined_object THEN
        -- Hacer nada si no existe
    END;

    BEGIN
        ALTER TABLE public.otp_profiles DROP CONSTRAINT fk_otp_profiles_owner;
    EXCEPTION WHEN undefined_object THEN
    END;
END $$;

-- 3. Añadir las nuevas restricciones con ON DELETE CASCADE
ALTER TABLE public.groups 
ADD CONSTRAINT fk_groups_owner 
FOREIGN KEY (owner_id) 
REFERENCES public.users(id) 
ON DELETE CASCADE;

ALTER TABLE public.otp_profiles 
ADD CONSTRAINT fk_otp_profiles_owner 
FOREIGN KEY (owner_id) 
REFERENCES public.users(id) 
ON DELETE CASCADE;

