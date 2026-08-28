-- Habilitar el bucket "tickets_evidence"
INSERT INTO storage.buckets (id, name, public)
VALUES ('tickets_evidence', 'tickets_evidence', true)
ON CONFLICT (id) DO NOTHING;

-- Políticas de seguridad para el bucket "tickets_evidence"

-- 1. Permitir lectura pública a cualquier archivo de evidencia
CREATE POLICY "Public Access to Tickets Evidence"
ON storage.objects FOR SELECT
USING (bucket_id = 'tickets_evidence');

-- 2. Permitir inserción solo a usuarios autenticados
CREATE POLICY "Authenticated users can upload tickets evidence"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'tickets_evidence');
