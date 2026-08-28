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
