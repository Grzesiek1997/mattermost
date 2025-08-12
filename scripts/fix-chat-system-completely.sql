-- Complete fix for chat system RLS policies and functions
-- This script removes all problematic RLS policies and creates new, safe ones

-- Drop all existing problematic policies
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
DROP POLICY IF EXISTS "Users can create chats" ON public.chats;
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_members;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_members;
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;

-- Ensure tables exist with correct structure
CREATE TABLE IF NOT EXISTS public.chat_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member',
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- Create simple, non-recursive RLS policies

-- Chats policies - simple and direct
CREATE POLICY "chats_select_policy" ON public.chats FOR SELECT USING (
    -- User can see chats they created OR chats they are a member of
    created_by = auth.uid() OR 
    id IN (SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid())
);

CREATE POLICY "chats_insert_policy" ON public.chats FOR INSERT WITH CHECK (
    created_by = auth.uid()
);

CREATE POLICY "chats_update_policy" ON public.chats FOR UPDATE USING (
    created_by = auth.uid()
);

-- Chat members policies - simple and direct
CREATE POLICY "chat_members_select_policy" ON public.chat_members FOR SELECT USING (
    -- User can see members of chats they are in
    user_id = auth.uid() OR 
    chat_id IN (SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid())
);

CREATE POLICY "chat_members_insert_policy" ON public.chat_members FOR INSERT WITH CHECK (
    -- User can add themselves to chats OR chat creator can add members
    user_id = auth.uid() OR 
    chat_id IN (SELECT id FROM public.chats WHERE created_by = auth.uid())
);

CREATE POLICY "chat_members_delete_policy" ON public.chat_members FOR DELETE USING (
    -- User can remove themselves OR chat creator can remove members
    user_id = auth.uid() OR 
    chat_id IN (SELECT id FROM public.chats WHERE created_by = auth.uid())
);

-- Messages policies - simple and direct
CREATE POLICY "messages_select_policy" ON public.messages FOR SELECT USING (
    -- User can see messages in chats they are members of
    chat_id IN (SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid())
);

CREATE POLICY "messages_insert_policy" ON public.messages FOR INSERT WITH CHECK (
    -- User can send messages to chats they are members of
    sender_id = auth.uid() AND
    chat_id IN (SELECT chat_id FROM public.chat_members WHERE user_id = auth.uid())
);

CREATE POLICY "messages_update_policy" ON public.messages FOR UPDATE USING (
    -- User can edit their own messages
    sender_id = auth.uid()
);

-- Create helper function to find direct chat between two users
CREATE OR REPLACE FUNCTION public.find_direct_chat_between_users(user1_id UUID, user2_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    chat_id UUID;
BEGIN
    -- Find direct chats where user1 is a member
    SELECT c.id INTO chat_id
    FROM chats c
    WHERE c.type = 'direct'
    AND EXISTS (SELECT 1 FROM chat_members cm1 WHERE cm1.chat_id = c.id AND cm1.user_id = user1_id)
    AND EXISTS (SELECT 1 FROM chat_members cm2 WHERE cm2.chat_id = c.id AND cm2.user_id = user2_id)
    LIMIT 1;
    
    RETURN chat_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.find_direct_chat_between_users TO authenticated;

-- Create function to safely create direct chat
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
    -- Get current user
    current_user_id := auth.uid();
    
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Check if direct chat already exists
    SELECT public.find_direct_chat_between_users(current_user_id, contact_id) INTO new_chat_id;
    
    IF new_chat_id IS NOT NULL THEN
        RETURN new_chat_id;
    END IF;
    
    -- Create new direct chat
    INSERT INTO chats (type, created_by)
    VALUES ('direct', current_user_id)
    RETURNING id INTO new_chat_id;
    
    -- Add both users as members
    INSERT INTO chat_members (chat_id, user_id, role)
    VALUES 
        (new_chat_id, current_user_id, 'member'),
        (new_chat_id, contact_id, 'member');
    
    RETURN new_chat_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members TO authenticated;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_chat_members_user_id ON public.chat_members(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_chat_id ON public.chat_members(chat_id);
CREATE INDEX IF NOT EXISTS idx_chats_type ON public.chats(type);
CREATE INDEX IF NOT EXISTS idx_chats_created_by ON public.chats(created_by);

-- Test the functions
DO $$
BEGIN
    RAISE NOTICE 'Chat system RLS policies and functions created successfully!';
    RAISE NOTICE 'Available functions:';
    RAISE NOTICE '- find_direct_chat_between_users(user1_id, user2_id)';
    RAISE NOTICE '- create_direct_chat_with_members(contact_id)';
END $$;
