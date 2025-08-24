-- Complete Telegram Clone Database Schema - Corrected Version
-- Following Supabase AI Assistant recommendations

-- 1. Install Extensions FIRST
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;

-- 2. Grant Schema Permissions EARLY
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT ALL ON SCHEMA public TO authenticated, service_role;

-- 3. Create Trigger Function EARLY (before tables that need it)
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

-- 4. Create Profiles Table EARLY (referenced by other tables)
CREATE TABLE public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
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

-- Enable RLS on profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Simple RLS policies for profiles (non-recursive)
CREATE POLICY "Users can view all profiles" ON public.profiles
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "Users can insert their own profile" ON public.profiles
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON public.profiles
    FOR UPDATE TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- 5. Create other tables in dependency order
CREATE TABLE public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text,
    description text,
    is_group boolean DEFAULT false,
    is_direct boolean DEFAULT true,
    created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.conversation_participants (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    role text DEFAULT 'member',
    joined_at timestamp with time zone DEFAULT now(),
    UNIQUE(conversation_id, user_id)
);

ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

-- Simple RLS policies for conversation_participants (avoiding recursion)
CREATE POLICY "Users can view their own participations" ON public.conversation_participants
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own participations" ON public.conversation_participants
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE TABLE public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
    sender_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    content text NOT NULL,
    message_type text DEFAULT 'text',
    reply_to_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
    is_edited boolean DEFAULT false,
    is_deleted boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Friend system tables
CREATE TABLE public.friend_requests (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    status text DEFAULT 'pending',
    message text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    UNIQUE(sender_id, receiver_id)
);

ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.friendships (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    friend_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at timestamp with time zone DEFAULT now(),
    UNIQUE(user_id, friend_id)
);

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

-- 6. Create SECURITY DEFINER functions to bypass RLS for complex operations
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
        AND username IN ('admin', 'administrator', 'super_admin')
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_conversations(p_user_id uuid)
RETURNS TABLE (
    conversation_id uuid,
    conversation_name text,
    is_group boolean,
    is_direct boolean,
    participant_count bigint,
    last_message_content text,
    last_message_time timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id as conversation_id,
        c.name as conversation_name,
        c.is_group,
        c.is_direct,
        COUNT(cp.user_id) as participant_count,
        (SELECT m.content FROM public.messages m 
         WHERE m.conversation_id = c.id 
         ORDER BY m.created_at DESC LIMIT 1) as last_message_content,
        (SELECT m.created_at FROM public.messages m 
         WHERE m.conversation_id = c.id 
         ORDER BY m.created_at DESC LIMIT 1) as last_message_time
    FROM public.conversations c
    JOIN public.conversation_participants cp ON c.id = cp.conversation_id
    WHERE cp.user_id = p_user_id
    GROUP BY c.id, c.name, c.is_group, c.is_direct, c.created_at
    ORDER BY last_message_time DESC NULLS LAST;
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
    SELECT p.id, p.username, p.full_name, p.avatar_url
    FROM public.profiles p
    WHERE p.username ILIKE '%' || search_term || '%'
       OR p.full_name ILIKE '%' || search_term || '%'
    LIMIT 20;
END;
$$;

-- 7. Create indexes for performance
CREATE INDEX idx_profiles_username ON public.profiles(username);
CREATE INDEX idx_conversation_participants_user_id ON public.conversation_participants(user_id);
CREATE INDEX idx_conversation_participants_conversation_id ON public.conversation_participants(conversation_id);
CREATE INDEX idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX idx_messages_sender_id ON public.messages(sender_id);
CREATE INDEX idx_messages_created_at ON public.messages(created_at);
CREATE INDEX idx_friend_requests_sender_id ON public.friend_requests(sender_id);
CREATE INDEX idx_friend_requests_receiver_id ON public.friend_requests(receiver_id);
CREATE INDEX idx_friendships_user_id ON public.friendships(user_id);
CREATE INDEX idx_friendships_friend_id ON public.friendships(friend_id);

-- 8. Create Trigger AFTER Profiles Table is Created
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 9. Grant permissions on all tables
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;

-- Success message
SELECT 'Database setup complete - corrected version with proper order and permissions!' as status;
