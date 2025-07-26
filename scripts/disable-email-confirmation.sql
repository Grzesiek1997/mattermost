-- Disable email confirmation for development
-- This allows users to sign up and sign in immediately without email verification

-- Update auth configuration to disable email confirmations
UPDATE auth.config 
SET enable_email_confirmations = false;

-- Alternative method if the above doesn't work
-- You can also set this in your Supabase dashboard:
-- Authentication > Settings > Email Auth > Enable email confirmations = OFF

-- Check current configuration
SELECT * FROM auth.config;

-- If you want to re-enable email confirmations later (for production):
-- UPDATE auth.config SET enable_email_confirmations = true;

-- Note: After running this script, restart your Supabase instance or wait a few minutes
-- for the changes to take effect.
