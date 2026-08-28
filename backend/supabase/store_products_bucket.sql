-- Script para crear y configurar el bucket de Store Products (IA) en Supabase Storage
-- Ejecutar en el SQL Editor de Supabase

-- 1. Crear el bucket si no existe
insert into storage.buckets (id, name, public)
values ('store_products', 'store_products', true)
on conflict (id) do nothing;

-- 2. Eliminar políticas anteriores (opcional, para evitar conflictos si se vuelve a correr)
drop policy if exists "Public Access for store_products" on storage.objects;
drop policy if exists "Authenticated users can upload store_products" on storage.objects;
drop policy if exists "Users can update their own store_products" on storage.objects;
drop policy if exists "Users can delete their own store_products" on storage.objects;

-- 3. Permitir acceso público a la lectura de las imágenes (cualquiera puede ver las portadas en la tienda)
create policy "Public Access for store_products"
on storage.objects for select
to authenticated
using ( bucket_id = 'store_products' );

-- Alternativamente, si queremos que usuarios NO logueados también vean la tienda:
create policy "Anon Access for store_products"
on storage.objects for select
to anon
using ( bucket_id = 'store_products' );

-- 4. Permitir subir imágenes solo a usuarios autenticados
create policy "Authenticated users can upload store_products"
on storage.objects for insert
to authenticated
with check ( bucket_id = 'store_products' );

-- 5. Permitir a los usuarios editar/eliminar sus propios archivos (basado en el token JWT / user id)
create policy "Users can update their own store_products"
on storage.objects for update
to authenticated
using ( auth.uid() = owner );

create policy "Users can delete their own store_products"
on storage.objects for delete
to authenticated
using ( auth.uid() = owner );
