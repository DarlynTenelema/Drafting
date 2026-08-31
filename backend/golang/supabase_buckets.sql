-- SQL script to create the 'chat_coach' bucket in Supabase and set up public access policies

-- Create the bucket for storing chat coach screenshots
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat_coach', 'chat_coach', true)
ON CONFLICT (id) DO NOTHING;

-- Policy to allow public access to view images
CREATE POLICY "Public Access"
ON storage.objects FOR SELECT
USING ( bucket_id = 'chat_coach' );

-- Policy to allow authenticated users (via service role) to insert images
CREATE POLICY "Service Role Insert Access"
ON storage.objects FOR INSERT
WITH CHECK ( bucket_id = 'chat_coach' );

-- Note: Since the backend uses the service role key to upload, 
-- it automatically bypasses RLS policies, but the SELECT policy is needed 
-- for the public URLs to work on the frontend.

-- Create additional buckets used by the Flutter frontend
INSERT INTO storage.buckets (id, name, public)
VALUES 
  ('store_products', 'store_products', true),
  ('avatars', 'avatars', true),
  ('support_tickets', 'support_tickets', true),
  ('fanarts', 'fanarts', true)
ON CONFLICT (id) DO NOTHING;

-- Policy to allow public access to view images from new buckets
CREATE POLICY "Public Access New Buckets"
ON storage.objects FOR SELECT
USING ( bucket_id IN ('store_products', 'avatars', 'support_tickets', 'fanarts') );

-- Policy to allow public inserts from Flutter app (Anon key)
CREATE POLICY "Public Insert Access"
ON storage.objects FOR INSERT
WITH CHECK ( bucket_id IN ('store_products', 'avatars', 'support_tickets', 'fanarts', 'chat_coach') );
