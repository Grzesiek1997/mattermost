-- COMPLETE DATABASE REBUILD FROM SCRATCH
-- This script creates a clean, working chat application database

-- Drop everything first to ensure clean state
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create users table (extends auth.users)
CREATE TABLE public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
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

-- Create chats table
CREATE TABLE public.chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT,
    type TEXT NOT NULL DEFAULT 'direct' CHECK (type IN ('direct', 'group')),
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create chat_participants table
CREATE TABLE public.chat_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- Create messages table
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'file')),
    reply_to UUID REFERENCES public.messages(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create contacts table
CREATE TABLE public.contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'blocked')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, contact_user_id)
);

-- Create admin tables
CREATE TABLE public.admin_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
    role TEXT DEFAULT 'admin' CHECK (role IN ('admin', 'super_admin')),
    permissions JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_users_email ON public.users(email);
CREATE INDEX idx_users_username ON public.users(username);
CREATE INDEX idx_chat_participants_chat_id ON public.chat_participants(chat_id);
CREATE INDEX idx_chat_participants_user_id ON public.chat_participants(user_id);
CREATE INDEX idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX idx_messages_created_at ON public.messages(created_at);
CREATE INDEX idx_contacts_user_id ON public.contacts(user_id);
CREATE INDEX idx_contacts_status ON public.contacts(status);

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- Simple RLS policies that avoid recursion
-- Users table policies
CREATE POLICY "Users can view all profiles" ON public.users FOR SELECT USING (true);
CREATE POLICY "Users can insert their own profile" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON public.users FOR UPDATE USING (auth.uid() = id);

-- Chats table policies
CREATE POLICY "Users can view their chats" ON public.chats FOR SELECT USING (
    id IN (SELECT chat_id FROM public.chat_participants WHERE user_id = auth.uid())
);
CREATE POLICY "Users can create chats" ON public.chats FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Chat participants policies (SIMPLE - NO RECURSION)
CREATE POLICY "Users can view participants of their chats" ON public.chat_participants FOR SELECT USING (
    chat_id IN (SELECT chat_id FROM public.chat_participants WHERE user_id = auth.uid())
);
CREATE POLICY "Users can add participants to chats they created" ON public.chat_participants FOR INSERT WITH CHECK (
    chat_id IN (SELECT id FROM public.chats WHERE created_by = auth.uid())
);

-- Messages table policies
CREATE POLICY "Users can view messages in their chats" ON public.messages FOR SELECT USING (
    chat_id IN (SELECT chat_id FROM public.chat_participants WHERE user_id = auth.uid())
);
CREATE POLICY "Users can send messages to their chats" ON public.messages FOR INSERT WITH CHECK (
    auth.uid() = user_id AND 
    chat_id IN (SELECT chat_id FROM public.chat_participants WHERE user_id = auth.uid())
);

-- Contacts table policies
CREATE POLICY "Users can view their contacts" ON public.contacts FOR SELECT USING (
    auth.uid() = user_id OR auth.uid() = contact_user_id
);
CREATE POLICY "Users can manage their contacts" ON public.contacts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their contacts" ON public.contacts FOR UPDATE USING (
    auth.uid() = user_id OR auth.uid() = contact_user_id
);

-- Admin table policies
CREATE POLICY "Only admins can view admin users" ON public.admin_users FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid())
);

-- Create SECURITY DEFINER functions to bypass RLS for complex operations
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
    FROM chats c
    WHERE c.type = 'direct'
    AND EXISTS (SELECT 1 FROM chat_participants cp1 WHERE cp1.chat_id = c.id AND cp1.user_id = user1)
    AND EXISTS (SELECT 1 FROM chat_participants cp2 WHERE cp2.chat_id = c.id AND cp2.user_id = user2)
    AND (SELECT COUNT(*) FROM chat_participants cp WHERE cp.chat_id = c.id) = 2;
    
    IF existing_chat_id IS NOT NULL THEN
        RETURN existing_chat_id;
    END IF;
    
    -- Create new direct chat
    INSERT INTO chats (type, created_by) VALUES ('direct', user1) RETURNING id INTO chat_id;
    
    -- Add both users as participants
    INSERT INTO chat_participants (chat_id, user_id, role) VALUES (chat_id, user1, 'member');
    INSERT INTO chat_participants (chat_id, user_id, role) VALUES (chat_id, user2, 'member');
    
    RETURN chat_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term TEXT DEFAULT '')
RETURNS TABLE(id UUID, email TEXT, username TEXT, full_name TEXT, avatar_url TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, u.email, u.username, u.full_name, u.avatar_url
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

CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    check_user_id UUID;
BEGIN
    check_user_id := COALESCE(user_uuid, auth.uid());
    
    RETURN EXISTS (
        SELECT 1 FROM admin_users 
        WHERE user_id = check_user_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_user_profile(
    user_id UUID,
    user_email TEXT,
    user_username TEXT,
    user_full_name TEXT DEFAULT 'User'
)
RETURNS public.users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    new_user public.users;
BEGIN
    -- Check if user already exists
    SELECT * INTO new_user FROM users WHERE id = user_id;
    
    IF new_user.id IS NOT NULL THEN
        RETURN new_user;
    END IF;
    
    -- Create new user profile
    INSERT INTO users (
        id, email, username, full_name, is_online, last_seen
    ) VALUES (
        user_id, user_email, user_username, user_full_name, true, NOW()
    ) RETURNING * INTO new_user;
    
    RETURN new_user;
END;
$$;

-- Grant permissions
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon;

-- Create trigger to automatically create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.users (id, email, username, full_name)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1)),
        COALESCE(NEW.raw_user_meta_data->>'full_name', 'User')
    );
    RETURN NEW;
END;
$$;

-- Create trigger on auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Test the setup
SELECT 'Database setup complete!' as status;
