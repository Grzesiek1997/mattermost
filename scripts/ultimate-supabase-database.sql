-- Ultimate Supabase Database Schema for Telegram-like Messenger
-- Based on complete Supabase documentation and best practices

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Drop existing objects in correct order to avoid dependency issues
DROP POLICY IF EXISTS "Users can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can create conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can view conversation participants" ON public.conversation_participants;
DROP POLICY IF EXISTS "Users can join conversations" ON public.conversation_participants;
DROP POLICY IF EXISTS "Users can view messages in their conversations" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
DROP POLICY IF EXISTS "Users can view friendships" ON public.friendships;
DROP POLICY IF EXISTS "Users can create friendships" ON public.friendships;
DROP POLICY IF EXISTS "Users can view friend requests" ON public.friend_requests;
DROP POLICY IF EXISTS "Users can send friend requests" ON public.friend_requests;
DROP POLICY IF EXISTS "Users can respond to friend requests" ON public.friend_requests;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_user_conversations(uuid);
DROP FUNCTION IF EXISTS public.search_users(text);
DROP FUNCTION IF EXISTS public.send_friend_request(uuid);
DROP FUNCTION IF EXISTS public.accept_friend_request(uuid);
DROP FUNCTION IF EXISTS public.reject_friend_request(uuid);
DROP FUNCTION IF EXISTS public.is_admin(uuid);

DROP TABLE IF EXISTS public.message_reactions CASCADE;
DROP TABLE IF EXISTS public.message_attachments CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.conversation_participants CASCADE;
DROP TABLE IF EXISTS public.conversations CASCADE;
DROP TABLE IF EXISTS public.friend_requests CASCADE;
DROP TABLE IF EXISTS public.friendships CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

-- Create profiles table (must be first due to foreign key dependencies)
CREATE TABLE public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    full_name TEXT,
    avatar_url TEXT,
    bio TEXT,
    phone TEXT,
    status TEXT DEFAULT 'offline' CHECK (status IN ('online', 'offline', 'away', 'busy')),
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    is_admin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create conversations table
CREATE TABLE public.conversations (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT,
    description TEXT,
    is_group BOOLEAN DEFAULT FALSE,
    avatar_url TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create conversation_participants table
CREATE TABLE public.conversation_participants (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'moderator', 'member')),
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    last_read_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(conversation_id, user_id)
);

-- Create messages table
CREATE TABLE public.messages (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'file', 'audio', 'video')),
    reply_to_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    is_edited BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create friendships table
CREATE TABLE public.friendships (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    friend_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, friend_id),
    CHECK (user_id != friend_id)
);

-- Create friend_requests table
CREATE TABLE public.friend_requests (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    sender_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(sender_id, receiver_id),
    CHECK (sender_id != receiver_id)
);

-- Create message_attachments table
CREATE TABLE public.message_attachments (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_url TEXT NOT NULL,
    file_type TEXT NOT NULL,
    file_size BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create message_reactions table
CREATE TABLE public.message_reactions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    reaction TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(message_id, user_id, reaction)
);

-- Create indexes for performance
CREATE INDEX idx_profiles_username ON public.profiles(username);
CREATE INDEX idx_profiles_status ON public.profiles(status);
CREATE INDEX idx_conversations_created_by ON public.conversations(created_by);
CREATE INDEX idx_conversation_participants_conversation_id ON public.conversation_participants(conversation_id);
CREATE INDEX idx_conversation_participants_user_id ON public.conversation_participants(user_id);
CREATE INDEX idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX idx_messages_sender_id ON public.messages(sender_id);
CREATE INDEX idx_messages_created_at ON public.messages(created_at);
CREATE INDEX idx_friendships_user_id ON public.friendships(user_id);
CREATE INDEX idx_friendships_friend_id ON public.friendships(friend_id);
CREATE INDEX idx_friend_requests_sender_id ON public.friend_requests(sender_id);
CREATE INDEX idx_friend_requests_receiver_id ON public.friend_requests(receiver_id);
CREATE INDEX idx_friend_requests_status ON public.friend_requests(status);

-- Enable Row Level Security on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

-- Create RLS Policies for profiles
CREATE POLICY "Users can view all profiles" ON public.profiles
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "Users can insert own profile" ON public.profiles
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Create RLS Policies for conversations
CREATE POLICY "Users can view own conversations" ON public.conversations
    FOR SELECT TO authenticated
    USING (
        id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create conversations" ON public.conversations
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Users can update own conversations" ON public.conversations
    FOR UPDATE TO authenticated
    USING (
        id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid() AND role IN ('admin', 'moderator')
        )
    );

-- Create RLS Policies for conversation_participants
CREATE POLICY "Users can view conversation participants" ON public.conversation_participants
    FOR SELECT TO authenticated
    USING (
        conversation_id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can join conversations" ON public.conversation_participants
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Create RLS Policies for messages
CREATE POLICY "Users can view messages in their conversations" ON public.messages
    FOR SELECT TO authenticated
    USING (
        conversation_id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can send messages" ON public.messages
    FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid() = sender_id AND
        conversation_id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update own messages" ON public.messages
    FOR UPDATE TO authenticated
    USING (auth.uid() = sender_id)
    WITH CHECK (auth.uid() = sender_id);

-- Create RLS Policies for friendships
CREATE POLICY "Users can view friendships" ON public.friendships
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id OR auth.uid() = friend_id);

CREATE POLICY "Users can create friendships" ON public.friendships
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Create RLS Policies for friend_requests
CREATE POLICY "Users can view friend requests" ON public.friend_requests
    FOR SELECT TO authenticated
    USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

CREATE POLICY "Users can send friend requests" ON public.friend_requests
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can respond to friend requests" ON public.friend_requests
    FOR UPDATE TO authenticated
    USING (auth.uid() = receiver_id)
    WITH CHECK (auth.uid() = receiver_id);

-- Create RLS Policies for message_attachments
CREATE POLICY "Users can view attachments in their conversations" ON public.message_attachments
    FOR SELECT TO authenticated
    USING (
        message_id IN (
            SELECT m.id 
            FROM public.messages m
            JOIN public.conversation_participants cp ON m.conversation_id = cp.conversation_id
            WHERE cp.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can add attachments to their messages" ON public.message_attachments
    FOR INSERT TO authenticated
    WITH CHECK (
        message_id IN (
            SELECT id 
            FROM public.messages 
            WHERE sender_id = auth.uid()
        )
    );

-- Create RLS Policies for message_reactions
CREATE POLICY "Users can view reactions in their conversations" ON public.message_reactions
    FOR SELECT TO authenticated
    USING (
        message_id IN (
            SELECT m.id 
            FROM public.messages m
            JOIN public.conversation_participants cp ON m.conversation_id = cp.conversation_id
            WHERE cp.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can add reactions" ON public.message_reactions
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove own reactions" ON public.message_reactions
    FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- Create SECURITY DEFINER functions to bypass RLS for complex operations
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.profiles (id, username, full_name, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'username', NEW.email),
        COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
        COALESCE(NEW.raw_user_meta_data->>'avatar_url', '')
    );
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_conversations(p_user_id UUID)
RETURNS TABLE (
    id UUID,
    name TEXT,
    description TEXT,
    is_group BOOLEAN,
    avatar_url TEXT,
    created_by UUID,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    last_message_content TEXT,
    last_message_at TIMESTAMPTZ,
    unread_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.name,
        c.description,
        c.is_group,
        c.avatar_url,
        c.created_by,
        c.created_at,
        c.updated_at,
        lm.content as last_message_content,
        lm.created_at as last_message_at,
        COALESCE(unread.count, 0) as unread_count
    FROM public.conversations c
    JOIN public.conversation_participants cp ON c.id = cp.conversation_id
    LEFT JOIN LATERAL (
        SELECT content, created_at
        FROM public.messages m
        WHERE m.conversation_id = c.id
        ORDER BY m.created_at DESC
        LIMIT 1
    ) lm ON true
    LEFT JOIN LATERAL (
        SELECT COUNT(*) as count
        FROM public.messages m
        WHERE m.conversation_id = c.id
        AND m.created_at > cp.last_read_at
    ) unread ON true
    WHERE cp.user_id = p_user_id
    ORDER BY COALESCE(lm.created_at, c.created_at) DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.search_users(search_term TEXT)
RETURNS TABLE (
    id UUID,
    username TEXT,
    full_name TEXT,
    avatar_url TEXT,
    status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.username,
        p.full_name,
        p.avatar_url,
        p.status
    FROM public.profiles p
    WHERE 
        p.username ILIKE '%' || search_term || '%' OR
        p.full_name ILIKE '%' || search_term || '%'
    ORDER BY p.username
    LIMIT 50;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_friend_request(receiver_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    sender_id UUID := auth.uid();
    result JSON;
BEGIN
    -- Check if friendship already exists
    IF EXISTS (
        SELECT 1 FROM public.friendships 
        WHERE (user_id = sender_id AND friend_id = receiver_id)
        OR (user_id = receiver_id AND friend_id = sender_id)
    ) THEN
        result := json_build_object('success', false, 'message', 'Already friends');
        RETURN result;
    END IF;

    -- Check if request already exists
    IF EXISTS (
        SELECT 1 FROM public.friend_requests 
        WHERE sender_id = sender_id AND receiver_id = receiver_id
        AND status = 'pending'
    ) THEN
        result := json_build_object('success', false, 'message', 'Request already sent');
        RETURN result;
    END IF;

    -- Insert friend request
    INSERT INTO public.friend_requests (sender_id, receiver_id)
    VALUES (sender_id, receiver_id);

    result := json_build_object('success', true, 'message', 'Friend request sent');
    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_friend_request(request_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    req_sender_id UUID;
    req_receiver_id UUID;
    result JSON;
BEGIN
    -- Get request details
    SELECT sender_id, receiver_id INTO req_sender_id, req_receiver_id
    FROM public.friend_requests
    WHERE id = request_id AND receiver_id = auth.uid() AND status = 'pending';

    IF NOT FOUND THEN
        result := json_build_object('success', false, 'message', 'Request not found');
        RETURN result;
    END IF;

    -- Update request status
    UPDATE public.friend_requests
    SET status = 'accepted', updated_at = NOW()
    WHERE id = request_id;

    -- Create friendship (both directions)
    INSERT INTO public.friendships (user_id, friend_id)
    VALUES (req_sender_id, req_receiver_id), (req_receiver_id, req_sender_id);

    result := json_build_object('success', true, 'message', 'Friend request accepted');
    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_friend_request(request_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result JSON;
BEGIN
    UPDATE public.friend_requests
    SET status = 'rejected', updated_at = NOW()
    WHERE id = request_id AND receiver_id = auth.uid() AND status = 'pending';

    IF FOUND THEN
        result := json_build_object('success', true, 'message', 'Friend request rejected');
    ELSE
        result := json_build_object('success', false, 'message', 'Request not found');
    END IF;

    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    admin_status BOOLEAN;
BEGIN
    SELECT is_admin INTO admin_status
    FROM public.profiles
    WHERE id = user_uuid;

    RETURN COALESCE(admin_status, false);
END;
$$;

-- Create trigger for new user registration
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Enable Realtime for all tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.friendships;
ALTER PUBLICATION supabase_realtime ADD TABLE public.friend_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reactions;

-- Create test data (optional - remove in production)
-- This will only work if you have actual auth users
-- INSERT INTO public.profiles (id, username, full_name, avatar_url, is_admin)
-- VALUES 
--     ('00000000-0000-0000-0000-000000000001', 'admin', 'System Admin', '', true),
--     ('00000000-0000-0000-0000-000000000002', 'testuser', 'Test User', '', false)
-- ON CONFLICT (id) DO NOTHING;

-- Success message
SELECT 'Ultimate Supabase database setup complete with Realtime support!' as status;
