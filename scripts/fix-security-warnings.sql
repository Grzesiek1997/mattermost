-- Fix security warnings from Supabase database linter
-- This script fixes functions with mutable search_path

-- Fix add_chat_creator_as_owner function
CREATE OR REPLACE FUNCTION public.add_chat_creator_as_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Add the chat creator as an owner participant
    INSERT INTO public.chat_participants (chat_id, user_id, role)
    VALUES (NEW.id, NEW.created_by, 'owner')
    ON CONFLICT (chat_id, user_id) DO NOTHING;
    
    RETURN NEW;
END;
$$;

-- Fix update_chat_last_message function
CREATE OR REPLACE FUNCTION public.update_chat_last_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Update the chat's last_message_at timestamp
    UPDATE public.chats 
    SET 
        last_message_at = NEW.created_at,
        updated_at = NOW()
    WHERE id = NEW.chat_id;
    
    RETURN NEW;
END;
$$;

-- Fix update_user_last_seen function
CREATE OR REPLACE FUNCTION public.update_user_last_seen()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Update user's last_seen timestamp when they perform any action
    UPDATE public.users 
    SET 
        last_seen = NOW(),
        is_online = true
    WHERE id = auth.uid();
    
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Fix get_searchable_users function
CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term TEXT DEFAULT '')
RETURNS TABLE (
    id UUID,
    username TEXT,
    full_name TEXT,
    avatar_url TEXT,
    is_online BOOLEAN,
    last_seen TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.username,
        u.full_name,
        u.avatar_url,
        u.is_online,
        u.last_seen
    FROM public.users u
    WHERE 
        u.id != auth.uid() -- Exclude current user
        AND (
            search_term = '' 
            OR u.username ILIKE '%' || search_term || '%'
            OR u.full_name ILIKE '%' || search_term || '%'
        )
    ORDER BY 
        u.is_online DESC,
        u.last_seen DESC
    LIMIT 50;
END;
$$;

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION public.add_chat_creator_as_owner() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_chat_last_message() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_user_last_seen() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_searchable_users(TEXT) TO authenticated;

-- Verify functions are properly secured
SELECT 
    routine_name,
    routine_type,
    security_type,
    routine_definition LIKE '%SET search_path%' as has_search_path
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name IN (
    'add_chat_creator_as_owner',
    'update_chat_last_message', 
    'update_user_last_seen',
    'get_searchable_users'
);
