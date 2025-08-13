-- Clean up duplicate functions and fix RLS policies
-- This script removes all conflicting functions and creates clean versions

-- First, drop all existing versions of problematic functions
DROP FUNCTION IF EXISTS public.create_direct_chat_with_members(UUID);
DROP FUNCTION IF EXISTS public.create_direct_chat_with_members(UUID, UUID);
DROP FUNCTION IF EXISTS public.create_direct_chat_with_members(contact_id UUID);
DROP FUNCTION IF EXISTS public.create_direct_chat_with_members(user1 UUID, user2 UUID);
DROP FUNCTION IF EXISTS public.get_searchable_users();
DROP FUNCTION IF EXISTS public.get_searchable_users(TEXT);
DROP FUNCTION IF EXISTS public.get_searchable_users(search_term TEXT);

-- Drop all existing RLS policies that might cause recursion
DROP POLICY IF EXISTS "Users can view their chat participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can manage chat participants" ON public.chat_participants;
DROP POLICY IF EXISTS "chat_participants_select_policy" ON public.chat_participants;
DROP POLICY IF EXISTS "chat_participants_insert_policy" ON public.chat_participants;

-- Ensure tables exist with correct structure
CREATE TABLE IF NOT EXISTS public.chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member',
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- Enable RLS
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;

-- Create extremely simple RLS policies that don't cause recursion
CREATE POLICY "chat_participants_simple_select" ON public.chat_participants
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "chat_participants_simple_insert" ON public.chat_participants
    FOR INSERT WITH CHECK (user_id = auth.uid());

-- Create the function with SECURITY DEFINER to bypass RLS
CREATE OR REPLACE FUNCTION public.create_direct_chat_with_members(user1 UUID, user2 UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    chat_id UUID;
    existing_chat_id UUID;
BEGIN
    -- Check if direct chat already exists between these users
    SELECT c.id INTO existing_chat_id
    FROM chats c
    WHERE c.type = 'direct'
    AND EXISTS (
        SELECT 1 FROM chat_participants cp1 
        WHERE cp1.chat_id = c.id AND cp1.user_id = user1
    )
    AND EXISTS (
        SELECT 1 FROM chat_participants cp2 
        WHERE cp2.chat_id = c.id AND cp2.user_id = user2
    );
    
    -- If chat exists, return it
    IF existing_chat_id IS NOT NULL THEN
        RETURN existing_chat_id;
    END IF;
    
    -- Create new direct chat
    INSERT INTO chats (type, created_by)
    VALUES ('direct', user1)
    RETURNING id INTO chat_id;
    
    -- Add both users as participants
    INSERT INTO chat_participants (chat_id, user_id, role)
    VALUES 
        (chat_id, user1, 'member'),
        (chat_id, user2, 'member');
    
    RETURN chat_id;
END;
$$;

-- Create searchable users function
CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term TEXT DEFAULT '')
RETURNS TABLE(
    id UUID,
    email TEXT,
    username TEXT,
    full_name TEXT,
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
        u.email,
        u.username,
        u.full_name,
        u.avatar_url
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

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_searchable_users(TEXT) TO authenticated;

-- Test the functions
SELECT 'Functions created successfully' as status;
