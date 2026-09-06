-- Script para crear y configurar el bucket de Fanarts en Supabase Storage
-- Ejecutar en el SQL Editor de Supabase

-- 1. Crear el bucket si no existe
insert into storage.buckets (id, name, public)
values ('fanarts', 'fanarts', true)
on conflict (id) do nothing;

-- 2. Eliminar políticas anteriores (opcional, para evitar conflictos si se vuelve a correr)
drop policy if exists "Public Access for fanarts" on storage.objects;
drop policy if exists "Authenticated users can upload fanarts" on storage.objects;
drop policy if exists "Users can update their own fanarts" on storage.objects;
drop policy if exists "Users can delete their own fanarts" on storage.objects;

-- 3. Permitir acceso público a la lectura de las imágenes (cualquiera puede ver el fanart)
create policy "Public Access for fanarts"
on storage.objects for select
to authenticated
using ( bucket_id = 'fanarts' );

-- 4. Permitir subir imágenes solo a usuarios autenticados (si Supabase Auth es usado)
-- Si usas tu propio sistema de tokens JWT, puedes necesitar ajustar esto
create policy "Authenticated users can upload fanarts"
on storage.objects for insert
with check ( bucket_id = 'fanarts' );

-- 5. Permitir a los usuarios editar/eliminar sus propios archivos
create policy "Users can update their own fanarts"
on storage.objects for update
using ( bucket_id = 'fanarts' AND auth.uid() = owner );
create policy "Users can delete their own fanarts"
on storage.objects for delete
using ( bucket_id = 'fanarts' AND auth.uid() = owner );
