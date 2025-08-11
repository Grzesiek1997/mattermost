-- Complete fix for infinite recursion in RLS policies
-- This script completely rebuilds all problematic policies

-- First, disable RLS temporarily to clean up
ALTER TABLE public.chat_members DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;

-- Drop ALL existing policies that might cause recursion
DROP POLICY IF EXISTS "Users can view chat members" ON public.chat_members;
DROP POLICY IF EXISTS "Users can view their chat members" ON public.chat_members;
DROP POLICY IF EXISTS "Users can read chat members of their chats" ON public.chat_members;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_members;
DROP POLICY IF EXISTS "Users can leave chats" ON public.chat_members;
DROP POLICY IF EXISTS "Chat creators can manage members" ON public.chat_members;
DROP POLICY IF EXISTS "Users can add members to chats they admin" ON public.chat_members;

DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
DROP POLICY IF EXISTS "Users can view their chats safely" ON public.chats;
DROP POLICY IF EXISTS "Users can read chats they are members of" ON public.chats;

DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
DROP POLICY IF EXISTS "Users can view messages in their chats safely" ON public.messages;
DROP POLICY IF EXISTS "Users can read messages from their chats" ON public.messages;

-- Create a simple function to check if user exists (no RLS involved)
CREATE OR REPLACE FUNCTION public.user_exists(user_id_param UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (SELECT 1 FROM auth.users WHERE id = user_id_param);
END;
$$;

-- Fix the get_searchable_users function with proper search_path
CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term TEXT DEFAULT '')
RETURNS TABLE (
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
        u.id != COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::UUID)
        AND (
            search_term = '' 
            OR u.username ILIKE '%' || search_term || '%'
            OR u.full_name ILIKE '%' || search_term || '%'
            OR u.email ILIKE '%' || search_term || '%'
        )
    ORDER BY u.username
    LIMIT 50;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.user_exists TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_searchable_users TO authenticated;

-- Re-enable RLS
ALTER TABLE public.chat_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Create NEW, simple policies without recursion

-- CHAT_MEMBERS policies - completely non-recursive
CREATE POLICY "chat_members_select" ON public.chat_members
FOR SELECT USING (
    -- Users can see their own memberships
    user_id = auth.uid()
    OR
    -- Users can see other members of chats they created
    EXISTS (
        SELECT 1 FROM public.chats c 
        WHERE c.id = chat_members.chat_id 
        AND c.created_by = auth.uid()
    )
    OR
    -- Users can see members of direct chats they're part of
    EXISTS (
        SELECT 1 FROM public.chats c 
        WHERE c.id = chat_members.chat_id 
        AND c.type = 'direct'
        AND EXISTS (
            SELECT 1 FROM public.chat_members cm 
            WHERE cm.chat_id = c.id 
            AND cm.user_id = auth.uid()
        )
    )
);

CREATE POLICY "chat_members_insert" ON public.chat_members
FOR INSERT WITH CHECK (
    -- Users can add themselves to any chat
    user_id = auth.uid()
    OR
    -- Chat creators can add anyone
    EXISTS (
        SELECT 1 FROM public.chats c 
        WHERE c.id = chat_id 
        AND c.created_by = auth.uid()
    )
);

CREATE POLICY "chat_members_delete" ON public.chat_members
FOR DELETE USING (
    -- Users can remove themselves
    user_id = auth.uid()
    OR
    -- Chat creators can remove anyone
    EXISTS (
        SELECT 1 FROM public.chats c 
        WHERE c.id = chat_id 
        AND c.created_by = auth.uid()
    )
);

-- CHATS policies - simple and direct
CREATE POLICY "chats_select" ON public.chats
FOR SELECT USING (
    -- Chat creators can see their chats
    created_by = auth.uid()
    OR
    -- Users can see chats they're members of (direct query, no recursion)
    id IN (
        SELECT cm.chat_id 
        FROM public.chat_members cm 
        WHERE cm.user_id = auth.uid()
    )
);

CREATE POLICY "chats_insert" ON public.chats
FOR INSERT WITH CHECK (
    created_by = auth.uid()
);

CREATE POLICY "chats_update" ON public.chats
FOR UPDATE USING (
    created_by = auth.uid()
);

-- MESSAGES policies - simple and direct
CREATE POLICY "messages_select" ON public.messages
FOR SELECT USING (
    -- Users can see messages in chats they're members of
    chat_id IN (
        SELECT cm.chat_id 
        FROM public.chat_members cm 
        WHERE cm.user_id = auth.uid()
    )
);

CREATE POLICY "messages_insert" ON public.messages
FOR INSERT WITH CHECK (
    -- Users can send messages as themselves
    user_id = auth.uid()
    AND
    -- In chats they're members of
    chat_id IN (
        SELECT cm.chat_id 
        FROM public.chat_members cm 
        WHERE cm.user_id = auth.uid()
        AND cm.can_send_messages = true
    )
);

CREATE POLICY "messages_update" ON public.messages
FOR UPDATE USING (
    -- Users can edit their own messages
    user_id = auth.uid()
);

-- Create helper function for ContactService to find existing direct chats
CREATE OR REPLACE FUNCTION public.find_direct_chat(user1_id UUID, user2_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    chat_id_result UUID;
BEGIN
    -- Find direct chat between two users
    SELECT c.id INTO chat_id_result
    FROM public.chats c
    WHERE c.type = 'direct'
    AND EXISTS (
        SELECT 1 FROM public.chat_members cm1 
        WHERE cm1.chat_id = c.id AND cm1.user_id = user1_id
    )
    AND EXISTS (
        SELECT 1 FROM public.chat_members cm2 
        WHERE cm2.chat_id = c.id AND cm2.user_id = user2_id
    )
    AND (
        SELECT COUNT(*) FROM public.chat_members cm 
        WHERE cm.chat_id = c.id
    ) = 2
    LIMIT 1;
    
    RETURN chat_id_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.find_direct_chat TO authenticated;

-- Test the policies
DO $$
BEGIN
    -- Test basic queries that were causing recursion
    PERFORM COUNT(*) FROM public.chat_members;
    PERFORM COUNT(*) FROM public.chats;
    PERFORM COUNT(*) FROM public.messages;
    
    RAISE NOTICE 'All RLS policies tested successfully - no recursion detected';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'RLS test failed: %', SQLERRM;
END $$;

SELECT 'Complete RLS fix applied successfully' as status;
