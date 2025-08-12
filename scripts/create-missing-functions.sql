-- Create missing database functions for chat system
-- Run this script in Supabase SQL Editor

-- Drop existing functions if they exist
DROP FUNCTION IF EXISTS public.create_direct_chat_with_members(UUID);
DROP FUNCTION IF EXISTS public.get_searchable_users(TEXT);

-- Create function to create direct chat with members
CREATE OR REPLACE FUNCTION public.create_direct_chat_with_members(contact_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    new_chat_id UUID;
    current_user_id UUID;
BEGIN
    -- Get current user ID
    current_user_id := auth.uid();
    
    -- Check if current user exists
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;
    
    -- Create new chat
    INSERT INTO public.chats (name, is_group, created_by)
    VALUES (NULL, false, current_user_id)
    RETURNING id INTO new_chat_id;
    
    -- Add current user as member
    INSERT INTO public.chat_members (chat_id, user_id)
    VALUES (new_chat_id, current_user_id);
    
    -- Add contact as member
    INSERT INTO public.chat_members (chat_id, user_id)
    VALUES (new_chat_id, contact_id);
    
    RETURN new_chat_id;
END;
$$;

-- Create function to search users
CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term TEXT)
RETURNS TABLE(
    id UUID,
    username TEXT,
    full_name TEXT,
    email TEXT,
    avatar_url TEXT
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
        u.email,
        u.avatar_url
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

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_searchable_users(TEXT) TO authenticated;

-- Test the functions
SELECT 'Functions created successfully' as status;
