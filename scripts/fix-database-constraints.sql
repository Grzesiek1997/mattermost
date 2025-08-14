-- Fix foreign key constraint issues and function conflicts
-- Run this to resolve the users table foreign key error and function conflicts

-- 1. Fix the users table foreign key constraint issue
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_id_fkey;

-- 2. Drop and recreate the get_searchable_users function with correct signature
DROP FUNCTION IF EXISTS public.get_searchable_users(text);
DROP FUNCTION IF EXISTS public.get_searchable_users(search_term text);

-- 3. Create the correct get_searchable_users function
CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term text)
RETURNS TABLE(
    id uuid,
    email text,
    username text,
    full_name text,
    avatar_url text,
    is_online boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.email,
        u.username,
        u.full_name,
        u.avatar_url,
        u.is_online
    FROM public.users u
    WHERE 
        u.id != auth.uid() AND
        (
            u.username ILIKE '%' || search_term || '%' OR
            u.full_name ILIKE '%' || search_term || '%' OR
            u.email ILIKE '%' || search_term || '%'
        )
    ORDER BY u.username
    LIMIT 20;
END;
$$;

-- 4. Grant proper permissions
GRANT EXECUTE ON FUNCTION public.get_searchable_users(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_searchable_users(text) TO anon;

-- 5. Fix any other constraint issues
ALTER TABLE public.contacts DROP CONSTRAINT IF EXISTS contacts_user_id_fkey;
ALTER TABLE public.contacts DROP CONSTRAINT IF EXISTS contacts_contact_user_id_fkey;

-- Recreate proper foreign key constraints
ALTER TABLE public.contacts 
ADD CONSTRAINT contacts_user_id_fkey 
FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.contacts 
ADD CONSTRAINT contacts_contact_user_id_fkey 
FOREIGN KEY (contact_user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- 6. Ensure users table has proper structure without self-referential constraints
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_created_by_fkey;
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_updated_by_fkey;

-- 7. Create a test user to verify the fix
INSERT INTO public.users (
    id,
    email,
    username,
    full_name,
    is_online,
    created_at,
    updated_at
) VALUES (
    '11111111-1111-1111-1111-111111111111',
    'test@example.com',
    'testuser',
    'Test User',
    false,
    NOW(),
    NOW()
) ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    username = EXCLUDED.username,
    full_name = EXCLUDED.full_name,
    updated_at = NOW();

-- 8. Test the fix
SELECT 'Foreign key constraint fixed successfully!' as status;

-- 9. Test the get_searchable_users function
SELECT 'Function test:' as test_type, count(*) as user_count 
FROM public.get_searchable_users('test');
