-- Supabase Cron Job: Delete Expired Products
-- Instrucciones: Ve al SQL Editor en Supabase, pega este código y ejecútalo.

-- Asegúrate de tener pg_cron habilitado:
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Programar eliminación diaria para Grupos normales
SELECT cron.schedule(
  'delete-expired-groups',
  '0 0 * * *', -- Todos los días a la medianoche (UTC)
  $$ DELETE FROM public.groups WHERE deletion_scheduled_for <= NOW(); $$
);

-- Programar eliminación diaria para OTPProfiles
SELECT cron.schedule(
  'delete-expired-otp',
  '0 0 * * *', -- Todos los días a la medianoche (UTC)
  $$ DELETE FROM public.otp_profiles WHERE deletion_scheduled_for <= NOW(); $$
);

-- Nota: Si usas GORM y tu tabla real se llama diferente (ej: group_profiles), ajusta el nombre.
-- GORM por defecto nombraría `groups` y `otp_profiles`.
