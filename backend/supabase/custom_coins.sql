-- 1. Tabla de Monedas Personalizadas (Custom Coins)
CREATE TABLE public.custom_coins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    value DECIMAL(10, 2) NOT NULL,
    image_url TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Índices
CREATE INDEX idx_custom_coins_user_id ON public.custom_coins(user_id);
CREATE INDEX idx_custom_coins_status ON public.custom_coins(status);

-- Trigger para updated_at
CREATE TRIGGER update_custom_coins_updated_at
BEFORE UPDATE ON public.custom_coins
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- 2. Configurar Storage Bucket para las texturas de las monedas
INSERT INTO storage.buckets (id, name, public) 
VALUES ('coin_textures', 'coin_textures', true)
ON CONFLICT (id) DO NOTHING;

-- Políticas de Seguridad (RLS) para el Storage Bucket
-- Permitir inserción a usuarios autenticados (opcionalmente ajustado a tu Auth)
CREATE POLICY "Allow public uploads to coin_textures" 
ON storage.objects FOR INSERT 
TO public
WITH CHECK (bucket_id = 'coin_textures');

-- Permitir lectura pública de las imágenes
CREATE POLICY "Allow public reads from coin_textures" 
ON storage.objects FOR SELECT 
TO authenticated
USING (bucket_id = 'coin_textures');
