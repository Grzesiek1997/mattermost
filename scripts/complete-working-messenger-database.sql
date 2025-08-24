-- Complete Telegram Clone Database Schema
-- Based on best practices from GitHub examples and Supabase documentation

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing objects to avoid conflicts
DROP POLICY IF EXISTS "Users can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view conversations they participate in" ON public.conversations;
DROP POLICY IF EXISTS "Users can create conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can view participants in their conversations" ON public.conversation_participants;
DROP POLICY IF EXISTS "Users can join conversations" ON public.conversation_participants;
DROP POLICY IF EXISTS "Users can view messages in their conversations" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages to their conversations" ON public.messages;
DROP POLICY IF EXISTS "Users can view their friendships" ON public.friendships;
DROP POLICY IF EXISTS "Users can create friendships" ON public.friendships;
DROP POLICY IF EXISTS "Users can view friend requests" ON public.friend_requests;
DROP POLICY IF EXISTS "Users can send friend requests" ON public.friend_requests;

DROP FUNCTION IF EXISTS public.is_admin(uuid);
DROP FUNCTION IF EXISTS public.get_user_conversations(uuid);
DROP FUNCTION IF EXISTS public.search_users(text);
DROP FUNCTION IF EXISTS public.send_friend_request(uuid, uuid);
DROP FUNCTION IF EXISTS public.accept_friend_request(uuid);
DROP FUNCTION IF EXISTS public.create_direct_conversation(uuid, uuid);

DROP TABLE IF EXISTS public.message_reactions CASCADE;
DROP TABLE IF EXISTS public.typing_indicators CASCADE;
DROP TABLE IF EXISTS public.message_reads CASCADE;
DROP TABLE IF EXISTS public.notifications CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.conversation_participants CASCADE;
DROP TABLE IF EXISTS public.conversations CASCADE;
DROP TABLE IF EXISTS public.friend_requests CASCADE;
DROP TABLE IF EXISTS public.friendships CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

-- Create profiles table (replaces users table)
CREATE TABLE public.profiles (
    id uuid REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    username text UNIQUE NOT NULL,
    full_name text,
    avatar_url text,
    bio text,
    phone text,
    status text DEFAULT 'offline',
    last_seen timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

-- Create conversations table
CREATE TABLE public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    type text NOT NULL CHECK (type IN ('direct', 'group')),
    title text,
    description text,
    avatar_url text,
    created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_message_at timestamp with time zone DEFAULT now()
);

-- Create conversation_participants table
CREATE TABLE public.conversation_participants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    role text DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    joined_at timestamp with time zone DEFAULT now(),
    UNIQUE(conversation_id, user_id)
);

-- Create messages table
CREATE TABLE public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    content text NOT NULL,
    message_type text DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'file', 'system')),
    reply_to_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
    edited_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

-- Create friendships table
CREATE TABLE public.friendships (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    friend_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at timestamp with time zone DEFAULT now(),
    UNIQUE(user_id, friend_id),
    CHECK (user_id != friend_id)
);

-- Create friend_requests table
CREATE TABLE public.friend_requests (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    sender_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    status text DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    UNIQUE(sender_id, receiver_id),
    CHECK (sender_id != receiver_id)
);

-- Create notifications table
CREATE TABLE public.notifications (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    type text NOT NULL CHECK (type IN ('friend_request', 'message', 'system')),
    title text NOT NULL,
    content text,
    data jsonb,
    read boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);

-- Create message_reads table
CREATE TABLE public.message_reads (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    message_id uuid REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    read_at timestamp with time zone DEFAULT now(),
    UNIQUE(message_id, user_id)
);

-- Create message_reactions table
CREATE TABLE public.message_reactions (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    message_id uuid REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    reaction text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    UNIQUE(message_id, user_id, reaction)
);

-- Create typing_indicators table
CREATE TABLE public.typing_indicators (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at timestamp with time zone DEFAULT now(),
    UNIQUE(conversation_id, user_id)
);

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;

-- Simple RLS policies for profiles (no recursion)
CREATE POLICY "Anyone can view profiles" ON public.profiles
    FOR SELECT USING (true);

CREATE POLICY "Users can insert their own profile" ON public.profiles
    FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON public.profiles
    FOR UPDATE USING (auth.uid() = id);

-- Simple RLS policies for conversations
CREATE POLICY "Users can view their conversations" ON public.conversations
    FOR SELECT USING (
        id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create conversations" ON public.conversations
    FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Simple RLS policies for conversation_participants
CREATE POLICY "Users can view participants in their conversations" ON public.conversation_participants
    FOR SELECT USING (
        conversation_id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can join conversations" ON public.conversation_participants
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Simple RLS policies for messages
CREATE POLICY "Users can view messages in their conversations" ON public.messages
    FOR SELECT USING (
        conversation_id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can send messages" ON public.messages
    FOR INSERT WITH CHECK (
        auth.uid() = user_id AND
        conversation_id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid()
        )
    );

-- Simple RLS policies for friendships
CREATE POLICY "Users can view their friendships" ON public.friendships
    FOR SELECT USING (auth.uid() = user_id OR auth.uid() = friend_id);

CREATE POLICY "Users can create friendships" ON public.friendships
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Simple RLS policies for friend_requests
CREATE POLICY "Users can view their friend requests" ON public.friend_requests
    FOR SELECT USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

CREATE POLICY "Users can send friend requests" ON public.friend_requests
    FOR INSERT WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can update received friend requests" ON public.friend_requests
    FOR UPDATE USING (auth.uid() = receiver_id);

-- Simple RLS policies for notifications
CREATE POLICY "Users can view their notifications" ON public.notifications
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update their notifications" ON public.notifications
    FOR UPDATE USING (auth.uid() = user_id);

-- Simple RLS policies for message_reads
CREATE POLICY "Users can view message reads in their conversations" ON public.message_reads
    FOR SELECT USING (
        message_id IN (
            SELECT m.id FROM public.messages m
            JOIN public.conversation_participants cp ON m.conversation_id = cp.conversation_id
            WHERE cp.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can mark messages as read" ON public.message_reads
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Simple RLS policies for message_reactions
CREATE POLICY "Users can view reactions in their conversations" ON public.message_reactions
    FOR SELECT USING (
        message_id IN (
            SELECT m.id FROM public.messages m
            JOIN public.conversation_participants cp ON m.conversation_id = cp.conversation_id
            WHERE cp.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can add reactions" ON public.message_reactions
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Simple RLS policies for typing_indicators
CREATE POLICY "Users can view typing indicators in their conversations" ON public.typing_indicators
    FOR SELECT USING (
        conversation_id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can set typing indicators" ON public.typing_indicators
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Create SECURITY DEFINER functions to bypass RLS for complex operations
CREATE OR REPLACE FUNCTION public.is_admin(user_uuid uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Simple admin check - you can customize this logic
    RETURN EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = user_uuid 
        AND username IN ('admin', 'administrator', 'root')
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_conversations(p_user_id uuid)
RETURNS TABLE (
    id uuid,
    type text,
    title text,
    avatar_url text,
    created_at timestamp with time zone,
    last_message_at timestamp with time zone,
    participant_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.type,
        c.title,
        c.avatar_url,
        c.created_at,
        c.last_message_at,
        COUNT(cp2.user_id) as participant_count
    FROM public.conversations c
    JOIN public.conversation_participants cp ON c.id = cp.conversation_id
    LEFT JOIN public.conversation_participants cp2 ON c.id = cp2.conversation_id
    WHERE cp.user_id = p_user_id
    GROUP BY c.id, c.type, c.title, c.avatar_url, c.created_at, c.last_message_at
    ORDER BY c.last_message_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.search_users(search_term text)
RETURNS TABLE (
    id uuid,
    username text,
    full_name text,
    avatar_url text
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
        p.avatar_url
    FROM public.profiles p
    WHERE 
        p.username ILIKE '%' || search_term || '%' OR
        p.full_name ILIKE '%' || search_term || '%'
    ORDER BY p.username
    LIMIT 20;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_friend_request(sender_id uuid, receiver_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    request_id uuid;
BEGIN
    -- Check if friendship already exists
    IF EXISTS (
        SELECT 1 FROM public.friendships 
        WHERE (user_id = sender_id AND friend_id = receiver_id) 
        OR (user_id = receiver_id AND friend_id = sender_id)
    ) THEN
        RAISE EXCEPTION 'Friendship already exists';
    END IF;

    -- Check if request already exists
    IF EXISTS (
        SELECT 1 FROM public.friend_requests 
        WHERE sender_id = send_friend_request.sender_id 
        AND receiver_id = send_friend_request.receiver_id 
        AND status = 'pending'
    ) THEN
        RAISE EXCEPTION 'Friend request already sent';
    END IF;

    -- Create friend request
    INSERT INTO public.friend_requests (sender_id, receiver_id)
    VALUES (send_friend_request.sender_id, send_friend_request.receiver_id)
    RETURNING id INTO request_id;

    -- Create notification
    INSERT INTO public.notifications (user_id, type, title, content, data)
    VALUES (
        receiver_id,
        'friend_request',
        'New Friend Request',
        'You have a new friend request',
        jsonb_build_object('request_id', request_id, 'sender_id', sender_id)
    );

    RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_friend_request(request_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    req_sender_id uuid;
    req_receiver_id uuid;
BEGIN
    -- Get request details
    SELECT sender_id, receiver_id INTO req_sender_id, req_receiver_id
    FROM public.friend_requests
    WHERE id = request_id AND status = 'pending';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Friend request not found or already processed';
    END IF;

    -- Update request status
    UPDATE public.friend_requests
    SET status = 'accepted', updated_at = now()
    WHERE id = request_id;

    -- Create friendship (both directions)
    INSERT INTO public.friendships (user_id, friend_id)
    VALUES (req_sender_id, req_receiver_id), (req_receiver_id, req_sender_id);

    -- Create notification for sender
    INSERT INTO public.notifications (user_id, type, title, content)
    VALUES (
        req_sender_id,
        'friend_request',
        'Friend Request Accepted',
        'Your friend request was accepted'
    );

    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_direct_conversation(user1_id uuid, user2_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    conversation_id uuid;
BEGIN
    -- Check if direct conversation already exists
    SELECT c.id INTO conversation_id
    FROM public.conversations c
    JOIN public.conversation_participants cp1 ON c.id = cp1.conversation_id
    JOIN public.conversation_participants cp2 ON c.id = cp2.conversation_id
    WHERE c.type = 'direct'
    AND cp1.user_id = user1_id
    AND cp2.user_id = user2_id
    AND (
        SELECT COUNT(*) FROM public.conversation_participants cp3 
        WHERE cp3.conversation_id = c.id
    ) = 2;

    IF conversation_id IS NOT NULL THEN
        RETURN conversation_id;
    END IF;

    -- Create new direct conversation
    INSERT INTO public.conversations (type, created_by)
    VALUES ('direct', user1_id)
    RETURNING id INTO conversation_id;

    -- Add both users as participants
    INSERT INTO public.conversation_participants (conversation_id, user_id)
    VALUES (conversation_id, user1_id), (conversation_id, user2_id);

    RETURN conversation_id;
END;
$$;

-- Create indexes for performance
CREATE INDEX idx_profiles_username ON public.profiles(username);
CREATE INDEX idx_profiles_full_name ON public.profiles(full_name);
CREATE INDEX idx_conversation_participants_user_id ON public.conversation_participants(user_id);
CREATE INDEX idx_conversation_participants_conversation_id ON public.conversation_participants(conversation_id);
CREATE INDEX idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX idx_messages_user_id ON public.messages(user_id);
CREATE INDEX idx_messages_created_at ON public.messages(created_at);
CREATE INDEX idx_friendships_user_id ON public.friendships(user_id);
CREATE INDEX idx_friendships_friend_id ON public.friendships(friend_id);
CREATE INDEX idx_friend_requests_sender_id ON public.friend_requests(sender_id);
CREATE INDEX idx_friend_requests_receiver_id ON public.friend_requests(receiver_id);
CREATE INDEX idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX idx_notifications_read ON public.notifications(read);

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Create trigger to automatically create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.profiles (id, username, full_name)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'username', NEW.email),
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

SELECT 'Database setup complete - comprehensive messaging app schema created!' as status;
