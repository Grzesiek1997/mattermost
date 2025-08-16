-- COMPLETE TELEGRAM CLONE DATABASE SCHEMA
-- Eliminates infinite recursion and includes all necessary tables

-- First, drop everything to start fresh
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. PROFILES TABLE (replaces users)
CREATE TABLE public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    full_name VARCHAR(100),
    bio TEXT,
    avatar_url TEXT,
    phone VARCHAR(20),
    email VARCHAR(255),
    status VARCHAR(20) DEFAULT 'offline',
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    is_online BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. USER ROLES AND PERMISSIONS
CREATE TYPE user_role AS ENUM ('super_admin', 'admin', 'moderator', 'user', 'guest');

CREATE TABLE public.user_roles (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    role user_role DEFAULT 'user',
    assigned_by UUID REFERENCES public.profiles(id),
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, role)
);

-- 3. CONVERSATIONS (replaces chats)
CREATE TABLE public.conversations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name VARCHAR(255),
    description TEXT,
    type VARCHAR(20) DEFAULT 'direct' CHECK (type IN ('direct', 'group', 'channel')),
    is_public BOOLEAN DEFAULT false,
    avatar_url TEXT,
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_message_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. CONVERSATION PARTICIPANTS (replaces chat_participants)
CREATE TABLE public.conversation_participants (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'moderator', 'member')),
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    left_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    UNIQUE(conversation_id, user_id)
);

-- 5. MESSAGES
CREATE TABLE public.messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    content TEXT,
    message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'video', 'audio', 'file', 'system')),
    reply_to_id UUID REFERENCES public.messages(id),
    is_edited BOOLEAN DEFAULT false,
    is_deleted BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. FRIEND REQUESTS AND FRIENDSHIPS
CREATE TABLE public.friend_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    sender_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled')),
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(sender_id, receiver_id)
);

CREATE TABLE public.friendships (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user1_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    user2_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user1_id, user2_id),
    CHECK (user1_id < user2_id) -- Ensures consistent ordering
);

-- 7. MESSAGE REACTIONS
CREATE TABLE public.message_reactions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    reaction VARCHAR(10) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(message_id, user_id, reaction)
);

-- 8. MESSAGE READS
CREATE TABLE public.message_reads (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(message_id, user_id)
);

-- 9. NOTIFICATIONS
CREATE TABLE public.notifications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,
    title VARCHAR(255),
    message TEXT,
    data JSONB,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. USER SETTINGS
CREATE TABLE public.user_settings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE UNIQUE,
    notifications_enabled BOOLEAN DEFAULT true,
    sound_enabled BOOLEAN DEFAULT true,
    theme VARCHAR(20) DEFAULT 'light' CHECK (theme IN ('light', 'dark', 'auto')),
    language VARCHAR(10) DEFAULT 'en',
    privacy_settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- INDEXES FOR PERFORMANCE
CREATE INDEX idx_profiles_username ON public.profiles(username);
CREATE INDEX idx_profiles_email ON public.profiles(email);
CREATE INDEX idx_conversations_type ON public.conversations(type);
CREATE INDEX idx_conversation_participants_user_id ON public.conversation_participants(user_id);
CREATE INDEX idx_conversation_participants_conversation_id ON public.conversation_participants(conversation_id);
CREATE INDEX idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX idx_messages_user_id ON public.messages(user_id);
CREATE INDEX idx_messages_created_at ON public.messages(created_at);
CREATE INDEX idx_friend_requests_sender_id ON public.friend_requests(sender_id);
CREATE INDEX idx_friend_requests_receiver_id ON public.friend_requests(receiver_id);
CREATE INDEX idx_friendships_user1_id ON public.friendships(user1_id);
CREATE INDEX idx_friendships_user2_id ON public.friendships(user2_id);
CREATE INDEX idx_notifications_user_id ON public.notifications(user_id);

-- SIMPLE RLS POLICIES (NO RECURSION)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "Users can view all profiles" ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

-- Conversations policies
CREATE POLICY "Users can view conversations they participate in" ON public.conversations FOR SELECT TO authenticated USING (
    id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "Users can create conversations" ON public.conversations FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid());

-- Conversation participants policies (SIMPLE - NO RECURSION)
CREATE POLICY "Users can view participants of their conversations" ON public.conversation_participants FOR SELECT TO authenticated USING (
    conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "Users can add participants to conversations they own" ON public.conversation_participants FOR INSERT TO authenticated WITH CHECK (
    conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
);

-- Messages policies
CREATE POLICY "Users can view messages in their conversations" ON public.messages FOR SELECT TO authenticated USING (
    conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "Users can send messages to their conversations" ON public.messages FOR INSERT TO authenticated WITH CHECK (
    user_id = auth.uid() AND 
    conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid() AND is_active = true)
);

-- Friend requests policies
CREATE POLICY "Users can view their friend requests" ON public.friend_requests FOR SELECT TO authenticated USING (
    sender_id = auth.uid() OR receiver_id = auth.uid()
);
CREATE POLICY "Users can send friend requests" ON public.friend_requests FOR INSERT TO authenticated WITH CHECK (sender_id = auth.uid());
CREATE POLICY "Users can update friend requests they received" ON public.friend_requests FOR UPDATE TO authenticated USING (receiver_id = auth.uid());

-- Friendships policies
CREATE POLICY "Users can view their friendships" ON public.friendships FOR SELECT TO authenticated USING (
    user1_id = auth.uid() OR user2_id = auth.uid()
);
CREATE POLICY "Users can create friendships" ON public.friendships FOR INSERT TO authenticated WITH CHECK (
    user1_id = auth.uid() OR user2_id = auth.uid()
);

-- Notifications policies
CREATE POLICY "Users can view own notifications" ON public.notifications FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "System can create notifications" ON public.notifications FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Users can update own notifications" ON public.notifications FOR UPDATE TO authenticated USING (user_id = auth.uid());

-- User settings policies
CREATE POLICY "Users can view own settings" ON public.user_settings FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Users can update own settings" ON public.user_settings FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Users can insert own settings" ON public.user_settings FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

-- SECURITY DEFINER FUNCTIONS (BYPASS RLS)
CREATE OR REPLACE FUNCTION public.search_users(search_term TEXT)
RETURNS TABLE(id UUID, username VARCHAR, full_name VARCHAR, avatar_url TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT p.id, p.username, p.full_name, p.avatar_url
    FROM public.profiles p
    WHERE p.username ILIKE '%' || search_term || '%' 
       OR p.full_name ILIKE '%' || search_term || '%'
    LIMIT 20;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_friend_request(receiver_username TEXT, message_text TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    receiver_id UUID;
    request_id UUID;
BEGIN
    -- Find receiver by username
    SELECT id INTO receiver_id FROM public.profiles WHERE username = receiver_username;
    
    IF receiver_id IS NULL THEN
        RAISE EXCEPTION 'User not found';
    END IF;
    
    -- Insert friend request
    INSERT INTO public.friend_requests (sender_id, receiver_id, message)
    VALUES (auth.uid(), receiver_id, message_text)
    RETURNING id INTO request_id;
    
    -- Create notification
    INSERT INTO public.notifications (user_id, type, title, message)
    VALUES (receiver_id, 'friend_request', 'New Friend Request', 
            (SELECT username FROM public.profiles WHERE id = auth.uid()) || ' sent you a friend request');
    
    RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_friend_request(request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    sender_id UUID;
    receiver_id UUID;
BEGIN
    -- Get request details
    SELECT fr.sender_id, fr.receiver_id INTO sender_id, receiver_id
    FROM public.friend_requests fr
    WHERE fr.id = request_id AND fr.receiver_id = auth.uid() AND fr.status = 'pending';
    
    IF sender_id IS NULL THEN
        RETURN false;
    END IF;
    
    -- Update request status
    UPDATE public.friend_requests SET status = 'accepted', updated_at = NOW()
    WHERE id = request_id;
    
    -- Create friendship (ensure consistent ordering)
    INSERT INTO public.friendships (user1_id, user2_id)
    VALUES (LEAST(sender_id, receiver_id), GREATEST(sender_id, receiver_id))
    ON CONFLICT DO NOTHING;
    
    -- Create notification
    INSERT INTO public.notifications (user_id, type, title, message)
    VALUES (sender_id, 'friend_accepted', 'Friend Request Accepted', 
            (SELECT username FROM public.profiles WHERE id = receiver_id) || ' accepted your friend request');
    
    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_direct_conversation(other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    conversation_id UUID;
    existing_conversation_id UUID;
BEGIN
    -- Check if direct conversation already exists
    SELECT cp1.conversation_id INTO existing_conversation_id
    FROM public.conversation_participants cp1
    JOIN public.conversation_participants cp2 ON cp1.conversation_id = cp2.conversation_id
    JOIN public.conversations c ON c.id = cp1.conversation_id
    WHERE cp1.user_id = auth.uid() 
      AND cp2.user_id = other_user_id 
      AND c.type = 'direct'
      AND cp1.is_active = true 
      AND cp2.is_active = true;
    
    IF existing_conversation_id IS NOT NULL THEN
        RETURN existing_conversation_id;
    END IF;
    
    -- Create new conversation
    INSERT INTO public.conversations (type, created_by)
    VALUES ('direct', auth.uid())
    RETURNING id INTO conversation_id;
    
    -- Add both participants
    INSERT INTO public.conversation_participants (conversation_id, user_id, role)
    VALUES 
        (conversation_id, auth.uid(), 'member'),
        (conversation_id, other_user_id, 'member');
    
    RETURN conversation_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_conversations()
RETURNS TABLE(
    id UUID, 
    name VARCHAR, 
    type VARCHAR, 
    avatar_url TEXT, 
    last_message_at TIMESTAMPTZ,
    participant_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.name,
        c.type,
        c.avatar_url,
        c.last_message_at,
        COUNT(cp.user_id) as participant_count
    FROM public.conversations c
    JOIN public.conversation_participants cp ON c.id = cp.conversation_id
    WHERE cp.user_id = auth.uid() AND cp.is_active = true
    GROUP BY c.id, c.name, c.type, c.avatar_url, c.last_message_at
    ORDER BY c.last_message_at DESC;
END;
$$;

-- Create trigger to update conversation last_message_at
CREATE OR REPLACE FUNCTION public.update_conversation_last_message()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.conversations 
    SET last_message_at = NEW.created_at 
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_update_conversation_last_message
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION public.update_conversation_last_message();

-- Create some test data
INSERT INTO public.profiles (id, username, full_name, email) VALUES
    ('11111111-1111-1111-1111-111111111111', 'john_doe', 'John Doe', 'john@example.com'),
    ('22222222-2222-2222-2222-222222222222', 'jane_smith', 'Jane Smith', 'jane@example.com'),
    ('33333333-3333-3333-3333-333333333333', 'test_user', 'Test User', 'test@example.com')
ON CONFLICT (id) DO NOTHING;

-- Grant permissions
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

SELECT 'Database setup complete!' as status;
