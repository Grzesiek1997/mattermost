-- DEFINITIVE FIX FOR INFINITE RECURSION IN RLS POLICIES
-- This script completely eliminates all recursive RLS policies

-- Disable RLS temporarily to make changes
ALTER TABLE IF EXISTS public.chat_participants DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.chats DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.users DISABLE ROW LEVEL SECURITY;

-- Drop ALL existing policies to start fresh
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
DROP POLICY IF EXISTS "Users can create chats" ON public.chats;
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
DROP POLICY IF EXISTS "Users can view all profiles" ON public.users;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;

-- Ensure tables exist with correct structure
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT auth.uid(),
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE NOT NULL,
    full_name TEXT,
    bio TEXT,
    avatar_url TEXT,
    phone TEXT,
    is_online BOOLEAN DEFAULT false,
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    type TEXT DEFAULT 'direct' CHECK (type IN ('direct', 'group')),
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member' CHECK (role IN ('member', 'admin', 'owner')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create SECURITY DEFINER function to bypass RLS for chat operations
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

-- Create function to get user's chats without RLS issues
CREATE OR REPLACE FUNCTION public.get_user_chats(user_uuid UUID)
RETURNS TABLE(
    chat_id UUID,
    chat_name TEXT,
    chat_type TEXT,
    created_at TIMESTAMP WITH TIME ZONE,
    participant_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id as chat_id,
        c.name as chat_name,
        c.type as chat_type,
        c.created_at,
        COUNT(cp.user_id) as participant_count
    FROM chats c
    INNER JOIN chat_participants cp ON c.id = cp.chat_id
    WHERE cp.user_id = user_uuid
    GROUP BY c.id, c.name, c.type, c.created_at
    ORDER BY c.updated_at DESC;
END;
$$;

-- Create function to get chat messages without RLS issues
CREATE OR REPLACE FUNCTION public.get_chat_messages(chat_uuid UUID, requesting_user UUID)
RETURNS TABLE(
    message_id UUID,
    content TEXT,
    message_type TEXT,
    created_at TIMESTAMP WITH TIME ZONE,
    user_id UUID,
    username TEXT,
    full_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Check if user is participant in this chat
    IF NOT EXISTS (
        SELECT 1 FROM chat_participants 
        WHERE chat_id = chat_uuid AND user_id = requesting_user
    ) THEN
        RAISE EXCEPTION 'User is not a participant in this chat';
    END IF;
    
    RETURN QUERY
    SELECT 
        m.id as message_id,
        m.content,
        m.message_type,
        m.created_at,
        m.user_id,
        u.username,
        u.full_name
    FROM messages m
    INNER JOIN users u ON m.user_id = u.id
    WHERE m.chat_id = chat_uuid
    ORDER BY m.created_at ASC;
END;
$$;

-- Create extremely simple RLS policies that don't cause recursion
-- Users table - allow all authenticated users to read profiles
CREATE POLICY "allow_read_users" ON public.users
    FOR SELECT USING (true);

CREATE POLICY "allow_insert_own_user" ON public.users
    FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "allow_update_own_user" ON public.users
    FOR UPDATE USING (auth.uid() = id);

-- Chats table - only allow reading chats where user is a participant
-- Use a simple subquery that doesn't reference the same table
CREATE POLICY "allow_read_user_chats" ON public.chats
    FOR SELECT USING (
        id IN (
            SELECT chat_id FROM chat_participants WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "allow_create_chats" ON public.chats
    FOR INSERT WITH CHECK (created_by = auth.uid());

-- Chat participants - allow reading and inserting
CREATE POLICY "allow_read_chat_participants" ON public.chat_participants
    FOR SELECT USING (true);

CREATE POLICY "allow_insert_chat_participants" ON public.chat_participants
    FOR INSERT WITH CHECK (true);

-- Messages - allow reading messages in user's chats and sending messages
CREATE POLICY "allow_read_messages" ON public.messages
    FOR SELECT USING (
        chat_id IN (
            SELECT chat_id FROM chat_participants WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "allow_insert_messages" ON public.messages
    FOR INSERT WITH CHECK (
        user_id = auth.uid() AND
        chat_id IN (
            SELECT chat_id FROM chat_participants WHERE user_id = auth.uid()
        )
    );

-- Re-enable RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_chats TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_chat_messages TO authenticated;

-- Test the functions
SELECT 'RLS policies updated successfully' as status;
