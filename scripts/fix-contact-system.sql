-- Fix contact system issues
-- This script ensures the contact invitation system works properly

-- Update the get_searchable_users function to match the ContactService call
CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term TEXT DEFAULT '')
RETURNS TABLE(id UUID, email TEXT, username TEXT, full_name TEXT, avatar_url TEXT, bio TEXT, phone TEXT, is_online BOOLEAN, last_seen TIMESTAMP WITH TIME ZONE, created_at TIMESTAMP WITH TIME ZONE, updated_at TIMESTAMP WITH TIME ZONE)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, u.email, u.username, u.full_name, u.avatar_url, u.bio, u.phone, u.is_online, u.last_seen, u.created_at, u.updated_at
    FROM users u
    WHERE u.id != auth.uid()
    AND (
        search_term = '' OR
        u.username ILIKE '%' || search_term || '%' OR
        u.full_name ILIKE '%' || search_term || '%' OR
        u.email ILIKE '%' || search_term || '%'
    )
    ORDER BY u.username
    LIMIT 50;
END;
$$;

-- Create some test users for testing the search functionality
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role)
VALUES 
  ('11111111-1111-1111-1111-111111111111', 'john.doe@example.com', crypt('password123', gen_salt('bf')), NOW(), NOW(), NOW(), '{"provider": "email", "providers": ["email"]}', '{"username": "johndoe", "full_name": "John Doe"}', false, 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'jane.smith@example.com', crypt('password123', gen_salt('bf')), NOW(), NOW(), NOW(), '{"provider": "email", "providers": ["email"]}', '{"username": "janesmith", "full_name": "Jane Smith"}', false, 'authenticated'),
  ('33333333-3333-3333-3333-333333333333', 'test.user@example.com', crypt('password123', gen_salt('bf')), NOW(), NOW(), NOW(), '{"provider": "email", "providers": ["email"]}', '{"username": "testuser", "full_name": "Test User"}', false, 'authenticated')
ON CONFLICT (id) DO NOTHING;

-- Create corresponding user profiles
INSERT INTO public.users (id, email, username, full_name, bio, is_online)
VALUES 
  ('11111111-1111-1111-1111-111111111111', 'john.doe@example.com', 'johndoe', 'John Doe', 'Software developer from New York', true),
  ('22222222-2222-2222-2222-222222222222', 'jane.smith@example.com', 'janesmith', 'Jane Smith', 'Designer and artist from California', false),
  ('33333333-3333-3333-3333-333333333333', 'test.user@example.com', 'testuser', 'Test User', 'Test account for development', true)
ON CONFLICT (id) DO NOTHING;

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION public.get_searchable_users TO authenticated, anon;

-- Test the function
SELECT 'Contact system setup complete!' as status;
SELECT 'Test users created: ' || COUNT(*) as test_users FROM public.users WHERE email LIKE '%@example.com';
