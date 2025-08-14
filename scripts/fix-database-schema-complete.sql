-- Complete database schema fix with missing columns and proper structure
-- This script will fix all database issues and create a working messenger system

-- Drop existing problematic policies and functions
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;

-- Drop and recreate contacts table with all required columns
DROP TABLE IF EXISTS public.contacts CASCADE;
CREATE TABLE public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'blocked')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    accepted_at TIMESTAMP WITH TIME ZONE,
    rejected_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(user_id, contact_user_id)
);

-- Add missing columns to existing tables if they don't exist
DO $$ 
BEGIN
    -- Add accepted_at to contacts if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'accepted_at') THEN
        ALTER TABLE public.contacts ADD COLUMN accepted_at TIMESTAMP WITH TIME ZONE;
    END IF;
    
    -- Add rejected_at to contacts if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'rejected_at') THEN
        ALTER TABLE public.contacts ADD COLUMN rejected_at TIMESTAMP WITH TIME ZONE;
    END IF;
END $$;

-- Create simple, non-recursive RLS policies
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

-- Simple contact policies without recursion
CREATE POLICY "Users can view their contacts" ON public.contacts
    FOR SELECT USING (auth.uid() = user_id OR auth.uid() = contact_user_id);

CREATE POLICY "Users can create contact invitations" ON public.contacts
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their contacts" ON public.contacts
    FOR UPDATE USING (auth.uid() = user_id OR auth.uid() = contact_user_id);

-- Simple chat_participants policies without recursion
CREATE POLICY "Users can view chat participants" ON public.chat_participants
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can join chats" ON public.chat_participants
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Simple messages policies without recursion
CREATE POLICY "Users can view messages" ON public.messages
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.chat_participants cp 
            WHERE cp.chat_id = messages.chat_id AND cp.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can send messages" ON public.messages
    FOR INSERT WITH CHECK (
        auth.uid() = user_id AND
        EXISTS (
            SELECT 1 FROM public.chat_participants cp 
            WHERE cp.chat_id = messages.chat_id AND cp.user_id = auth.uid()
        )
    );

-- Simple chats policies
CREATE POLICY "Users can view their chats" ON public.chats
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.chat_participants cp 
            WHERE cp.chat_id = chats.id AND cp.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create chats" ON public.chats
    FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Create SECURITY DEFINER functions to bypass RLS for complex operations
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
    FROM public.users u
    WHERE 
        u.id != COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::UUID)
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
    -- Check if direct chat already exists
    SELECT c.id INTO existing_chat_id
    FROM public.chats c
    WHERE c.type = 'direct'
    AND EXISTS (
        SELECT 1 FROM public.chat_participants cp1 
        WHERE cp1.chat_id = c.id AND cp1.user_id = user1
    )
    AND EXISTS (
        SELECT 1 FROM public.chat_participants cp2 
        WHERE cp2.chat_id = c.id AND cp2.user_id = user2
    );
    
    IF existing_chat_id IS NOT NULL THEN
        RETURN existing_chat_id;
    END IF;
    
    -- Create new direct chat
    INSERT INTO public.chats (type, created_by, created_at)
    VALUES ('direct', user1, NOW())
    RETURNING id INTO chat_id;
    
    -- Add both users as participants
    INSERT INTO public.chat_participants (chat_id, user_id, role, joined_at)
    VALUES 
        (chat_id, user1, 'member', NOW()),
        (chat_id, user2, 'member', NOW());
    
    RETURN chat_id;
END;
$$;

-- Create admin functions
CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_users 
        WHERE user_id = user_uuid AND is_active = true
    );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.get_searchable_users TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin TO authenticated;

-- Create test users for development
INSERT INTO public.users (id, email, username, full_name, created_at) VALUES
    ('11111111-1111-1111-1111-111111111111', 'john@test.com', 'john', 'John Doe', NOW()),
    ('22222222-2222-2222-2222-222222222222', 'jane@test.com', 'jane', 'Jane Smith', NOW()),
    ('33333333-3333-3333-3333-333333333333', 'test@test.com', 'test', 'Test User', NOW())
ON CONFLICT (id) DO NOTHING;

SELECT 'Database schema fixed successfully!' as status;
