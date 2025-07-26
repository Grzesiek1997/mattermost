-- Disable email confirmation for development
-- This script disables email confirmation in Supabase Auth settings
-- Run this in your Supabase SQL Editor to allow instant signup without email confirmation

-- Note: This is for development only. In production, you should keep email confirmation enabled.

-- Check current auth settings
SELECT * FROM auth.config;

-- Update auth settings to disable email confirmation
-- This allows users to sign up and sign in immediately without confirming their email
UPDATE auth.config 
SET 
  enable_signup = true,
  enable_confirmations = false,
  enable_email_confirmations = false
WHERE 
  id = 'auth';

-- Alternative: You can also set this in your Supabase Dashboard:
-- 1. Go to Authentication > Settings
-- 2. Under "User Signups" section
-- 3. Toggle OFF "Enable email confirmations"

-- Verify the changes
SELECT 
  enable_signup,
  enable_confirmations,
  enable_email_confirmations
FROM auth.config 
WHERE id = 'auth';

-- If you want to re-enable email confirmation later (for production):
-- UPDATE auth.config 
-- SET 
--   enable_confirmations = true,
--   enable_email_confirmations = true
-- WHERE 
--   id = 'auth';
