-- Script para crear y configurar el bucket de Avatares en Supabase Storage
-- Ejecutar en el SQL Editor de Supabase

-- 1. Crear el bucket si no existe
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- 2. Eliminar políticas anteriores (opcional, para evitar conflictos si se vuelve a correr)
drop policy if exists "Public Access for avatars" on storage.objects;
drop policy if exists "Authenticated users can upload avatars" on storage.objects;
drop policy if exists "Users can update their own avatars" on storage.objects;
drop policy if exists "Users can delete their own avatars" on storage.objects;

-- 3. Permitir acceso público a la lectura de las imágenes (cualquiera puede ver el avatar)
create policy "Public Access for avatars"
on storage.objects for select
to authenticated
using ( bucket_id = 'avatars' );

-- 4. Permitir subir imágenes a usuarios
create policy "Authenticated users can upload avatars"
on storage.objects for insert
with check ( bucket_id = 'avatars' );
