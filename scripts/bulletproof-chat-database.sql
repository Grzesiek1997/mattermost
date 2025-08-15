-- COMPLETE TELEGRAM CLONE DATABASE SETUP
-- This script creates everything needed for a full-featured messaging app
-- Run this in Supabase SQL Editor

-- =============================================================================
-- STEP 1: CLEAN SLATE - Remove everything that might conflict
-- =============================================================================

-- Drop all existing policies first
DROP POLICY IF EXISTS "Users can view profiles" ON public.users;
DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
DROP POLICY IF EXISTS "Users can create chats" ON public.chats;
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
DROP POLICY IF EXISTS "Users can manage contacts" ON public.contacts;
DROP POLICY IF EXISTS "Users can view contacts" ON public.contacts;

-- Drop all functions
DROP FUNCTION IF EXISTS public.get_user_chats(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.create_direct_chat_with_members(uuid, uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_searchable_users(text) CASCADE;
DROP FUNCTION IF EXISTS public.is_admin(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_admin_role(uuid) CASCADE;

-- Drop all tables in reverse dependency order
DROP TABLE IF EXISTS public.message_reactions CASCADE;
DROP TABLE IF EXISTS public.message_reads CASCADE;
DROP TABLE IF EXISTS public.typing_indicators CASCADE;
DROP TABLE IF EXISTS public.notifications CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.chat_participants CASCADE;
DROP TABLE IF EXISTS public.chats CASCADE;
DROP TABLE IF EXISTS public.contacts CASCADE;
DROP TABLE IF EXISTS public.user_roles CASCADE;
DROP TABLE IF EXISTS public.role_permissions CASCADE;
DROP TABLE IF EXISTS public.permissions CASCADE;
DROP TABLE IF EXISTS public.roles CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;

-- =============================================================================
-- STEP 2: CREATE CORE TABLES WITH ALL COLUMNS
-- =============================================================================

-- Users table (extends auth.users)
CREATE TABLE public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username text UNIQUE NOT NULL,
    full_name text,
    bio text,
    avatar_url text,
    phone text,
    status text DEFAULT 'offline' CHECK (status IN ('online', 'offline', 'away', 'busy')),
    last_seen timestamptz DEFAULT now(),
    is_verified boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Roles table
CREATE TABLE public.roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text UNIQUE NOT NULL,
    display_name text NOT NULL,
    description text,
    level integer NOT NULL DEFAULT 0,
    created_at timestamptz DEFAULT now()
);

-- Permissions table
CREATE TABLE public.permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text UNIQUE NOT NULL,
    description text,
    resource text NOT NULL,
    action text NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- Role permissions junction table
CREATE TABLE public.role_permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id uuid REFERENCES public.roles(id) ON DELETE CASCADE,
    permission_id uuid REFERENCES public.permissions(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now(),
    UNIQUE(role_id, permission_id)
);

-- User roles junction table
CREATE TABLE public.user_roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    role_id uuid REFERENCES public.roles(id) ON DELETE CASCADE,
    assigned_by uuid REFERENCES public.users(id),
    assigned_at timestamptz DEFAULT now(),
    expires_at timestamptz,
    UNIQUE(user_id, role_id)
);

-- Contacts table
CREATE TABLE public.contacts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    contact_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    status text DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'blocked', 'rejected')),
    invited_by uuid REFERENCES public.users(id),
    invited_at timestamptz DEFAULT now(),
    accepted_at timestamptz,
    blocked_at timestamptz,
    notes text,
    UNIQUE(user_id, contact_id)
);

-- Chats table
CREATE TABLE public.chats (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text,
    description text,
    type text DEFAULT 'direct' CHECK (type IN ('direct', 'group', 'channel', 'broadcast')),
    is_public boolean DEFAULT false,
    avatar_url text,
    created_by uuid REFERENCES public.users(id),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    last_message_at timestamptz DEFAULT now(),
    member_count integer DEFAULT 0,
    max_members integer DEFAULT 1000,
    settings jsonb DEFAULT '{}'::jsonb
);

-- Chat participants table
CREATE TABLE public.chat_participants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id uuid REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    role text DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'moderator', 'member', 'guest')),
    joined_at timestamptz DEFAULT now(),
    left_at timestamptz,
    invited_by uuid REFERENCES public.users(id),
    permissions jsonb DEFAULT '{}'::jsonb,
    is_muted boolean DEFAULT false,
    is_pinned boolean DEFAULT false,
    last_read_at timestamptz DEFAULT now(),
    UNIQUE(chat_id, user_id)
);

-- Messages table
CREATE TABLE public.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id uuid REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    content text,
    type text DEFAULT 'text' CHECK (type IN ('text', 'image', 'video', 'audio', 'file', 'location', 'contact', 'sticker', 'gif')),
    metadata jsonb DEFAULT '{}'::jsonb,
    reply_to uuid REFERENCES public.messages(id),
    forwarded_from uuid REFERENCES public.messages(id),
    edited_at timestamptz,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    expires_at timestamptz,
    is_system boolean DEFAULT false,
    thread_id uuid REFERENCES public.messages(id)
);

-- Message reactions table
CREATE TABLE public.message_reactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id uuid REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    emoji text NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE(message_id, user_id, emoji)
);

-- Message reads table
CREATE TABLE public.message_reads (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id uuid REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    read_at timestamptz DEFAULT now(),
    UNIQUE(message_id, user_id)
);

-- Typing indicators table
CREATE TABLE public.typing_indicators (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id uuid REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    started_at timestamptz DEFAULT now(),
    expires_at timestamptz DEFAULT (now() + interval '10 seconds'),
    UNIQUE(chat_id, user_id)
);

-- Notifications table
CREATE TABLE public.notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    type text NOT NULL CHECK (type IN ('message', 'contact_request', 'contact_accepted', 'chat_invite', 'mention', 'system')),
    title text NOT NULL,
    content text,
    data jsonb DEFAULT '{}'::jsonb,
    read_at timestamptz,
    created_at timestamptz DEFAULT now(),
    expires_at timestamptz
);

-- =============================================================================
-- STEP 3: CREATE INDEXES FOR PERFORMANCE
-- =============================================================================

-- Users indexes
CREATE INDEX idx_users_username ON public.users(username);
CREATE INDEX idx_users_status ON public.users(status);
CREATE INDEX idx_users_last_seen ON public.users(last_seen);

-- Contacts indexes
CREATE INDEX idx_contacts_user_id ON public.contacts(user_id);
CREATE INDEX idx_contacts_contact_id ON public.contacts(contact_id);
CREATE INDEX idx_contacts_status ON public.contacts(status);

-- Chats indexes
CREATE INDEX idx_chats_type ON public.chats(type);
CREATE INDEX idx_chats_created_by ON public.chats(created_by);
CREATE INDEX idx_chats_last_message_at ON public.chats(last_message_at);

-- Chat participants indexes
CREATE INDEX idx_chat_participants_chat_id ON public.chat_participants(chat_id);
CREATE INDEX idx_chat_participants_user_id ON public.chat_participants(user_id);
CREATE INDEX idx_chat_participants_role ON public.chat_participants(role);

-- Messages indexes
CREATE INDEX idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX idx_messages_user_id ON public.messages(user_id);
CREATE INDEX idx_messages_created_at ON public.messages(created_at);
CREATE INDEX idx_messages_type ON public.messages(type);

-- Notifications indexes
CREATE INDEX idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX idx_notifications_type ON public.notifications(type);
CREATE INDEX idx_notifications_read_at ON public.notifications(read_at);

-- =============================================================================
-- STEP 4: INSERT DEFAULT DATA
-- =============================================================================

-- Insert default roles
INSERT INTO public.roles (name, display_name, description, level) VALUES
('super_admin', 'Super Administrator', 'Full system access', 100),
('admin', 'Administrator', 'Administrative access', 80),
('moderator', 'Moderator', 'Content moderation access', 60),
('user', 'User', 'Standard user access', 20),
('guest', 'Guest', 'Limited access', 10)
ON CONFLICT (name) DO NOTHING;

-- Insert default permissions
INSERT INTO public.permissions (name, description, resource, action) VALUES
('users.read', 'Read user profiles', 'users', 'SELECT'),
('users.write', 'Update user profiles', 'users', 'UPDATE'),
('chats.create', 'Create new chats', 'chats', 'INSERT'),
('chats.read', 'Read chat information', 'chats', 'SELECT'),
('chats.update', 'Update chat settings', 'chats', 'UPDATE'),
('chats.delete', 'Delete chats', 'chats', 'DELETE'),
('messages.create', 'Send messages', 'messages', 'INSERT'),
('messages.read', 'Read messages', 'messages', 'SELECT'),
('messages.update', 'Edit messages', 'messages', 'UPDATE'),
('messages.delete', 'Delete messages', 'messages', 'DELETE'),
('admin.users', 'Manage users', 'admin', 'ALL'),
('admin.chats', 'Manage all chats', 'admin', 'ALL'),
('admin.system', 'System administration', 'admin', 'ALL')
ON CONFLICT (name) DO NOTHING;

-- Create test users
INSERT INTO public.users (id, username, full_name, bio, status) VALUES
('11111111-1111-1111-1111-111111111111', 'john_doe', 'John Doe', 'Test user for development', 'online'),
('22222222-2222-2222-2222-222222222222', 'jane_smith', 'Jane Smith', 'Another test user', 'online'),
('33333333-3333-3333-3333-333333333333', 'test_user', 'Test User', 'Testing account', 'offline')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- STEP 5: CREATE SECURITY DEFINER FUNCTIONS
-- =============================================================================

-- Function to get user chats (bypasses RLS)
CREATE OR REPLACE FUNCTION public.get_user_chats(p_user_id uuid)
RETURNS TABLE (
    chat_id uuid,
    chat_name text,
    chat_type text,
    chat_avatar_url text,
    last_message_at timestamptz,
    member_count integer,
    unread_count bigint
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
        c.member_count,
        COALESCE(
            (SELECT COUNT(*) 
             FROM messages m 
             WHERE m.chat_id = c.id 
             AND m.created_at > COALESCE(cp.last_read_at, cp.joined_at)
             AND m.user_id != p_user_id
            ), 0
        ) as unread_count
    FROM chats c
    INNER JOIN chat_participants cp ON c.id = cp.chat_id
    WHERE cp.user_id = p_user_id
    AND cp.left_at IS NULL
    ORDER BY c.last_message_at DESC;
END;
$$;

-- Function to create direct chat with members (bypasses RLS)
CREATE OR REPLACE FUNCTION public.create_direct_chat_with_members(p_user1 uuid, p_user2 uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_chat_id uuid;
    v_existing_chat_id uuid;
BEGIN
    -- Check if direct chat already exists
    SELECT c.id INTO v_existing_chat_id
    FROM chats c
    INNER JOIN chat_participants cp1 ON c.id = cp1.chat_id AND cp1.user_id = p_user1
    INNER JOIN chat_participants cp2 ON c.id = cp2.chat_id AND cp2.user_id = p_user2
    WHERE c.type = 'direct'
    AND c.member_count = 2
    LIMIT 1;
    
    IF v_existing_chat_id IS NOT NULL THEN
        RETURN v_existing_chat_id;
    END IF;
    
    -- Create new direct chat
    INSERT INTO chats (type, member_count, created_by)
    VALUES ('direct', 2, p_user1)
    RETURNING id INTO v_chat_id;
    
    -- Add both users as participants
    INSERT INTO chat_participants (chat_id, user_id, role)
    VALUES 
        (v_chat_id, p_user1, 'member'),
        (v_chat_id, p_user2, 'member');
    
    RETURN v_chat_id;
END;
$$;

-- Function to search users (bypasses RLS)
CREATE OR REPLACE FUNCTION public.get_searchable_users(p_search_term text)
RETURNS TABLE (
    id uuid,
    username text,
    full_name text,
    avatar_url text,
    status text,
    is_verified boolean
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
        u.avatar_url,
        u.status,
        u.is_verified
    FROM users u
    WHERE 
        u.username ILIKE '%' || p_search_term || '%'
        OR u.full_name ILIKE '%' || p_search_term || '%'
    ORDER BY u.username
    LIMIT 50;
END;
$$;

-- Function to check if user is admin
CREATE OR REPLACE FUNCTION public.is_admin(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin boolean := false;
BEGIN
    SELECT EXISTS(
        SELECT 1 
        FROM user_roles ur
        INNER JOIN roles r ON ur.role_id = r.id
        WHERE ur.user_id = p_user_id
        AND r.name IN ('super_admin', 'admin')
        AND (ur.expires_at IS NULL OR ur.expires_at > now())
    ) INTO v_is_admin;
    
    RETURN v_is_admin;
END;
$$;

-- =============================================================================
-- STEP 6: ENABLE RLS AND CREATE SIMPLE POLICIES
-- =============================================================================

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Users policies (simple and non-recursive)
CREATE POLICY "Users can view all profiles" ON public.users
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "Users can update own profile" ON public.users
    FOR UPDATE TO authenticated
    USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON public.users
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = id);

-- Contacts policies
CREATE POLICY "Users can manage their contacts" ON public.contacts
    FOR ALL TO authenticated
    USING (auth.uid() = user_id OR auth.uid() = contact_id);

-- Chats policies
CREATE POLICY "Users can view their chats" ON public.chats
    FOR SELECT TO authenticated
    USING (
        id IN (
            SELECT chat_id 
            FROM chat_participants 
            WHERE user_id = auth.uid() AND left_at IS NULL
        )
    );

CREATE POLICY "Users can create chats" ON public.chats
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = created_by);

-- Chat participants policies
CREATE POLICY "Users can view chat participants" ON public.chat_participants
    FOR SELECT TO authenticated
    USING (
        chat_id IN (
            SELECT chat_id 
            FROM chat_participants 
            WHERE user_id = auth.uid() AND left_at IS NULL
        )
    );

CREATE POLICY "Users can join chats" ON public.chat_participants
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Messages policies
CREATE POLICY "Users can view messages in their chats" ON public.messages
    FOR SELECT TO authenticated
    USING (
        chat_id IN (
            SELECT chat_id 
            FROM chat_participants 
            WHERE user_id = auth.uid() AND left_at IS NULL
        )
    );

CREATE POLICY "Users can send messages" ON public.messages
    FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid() = user_id 
        AND chat_id IN (
            SELECT chat_id 
            FROM chat_participants 
            WHERE user_id = auth.uid() AND left_at IS NULL
        )
    );

-- Notifications policies
CREATE POLICY "Users can view their notifications" ON public.notifications
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "System can create notifications" ON public.notifications
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- =============================================================================
-- STEP 7: CREATE TRIGGERS AND FUNCTIONS
-- =============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_chats_updated_at BEFORE UPDATE ON public.chats
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Function to update chat last_message_at
CREATE OR REPLACE FUNCTION public.update_chat_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.chats 
    SET last_message_at = NEW.created_at
    WHERE id = NEW.chat_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for chat last message
CREATE TRIGGER update_chat_last_message_trigger
    AFTER INSERT ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.update_chat_last_message();

-- =============================================================================
-- STEP 8: GRANT PERMISSIONS
-- =============================================================================

-- Grant usage on schema
GRANT USAGE ON SCHEMA public TO authenticated, anon;

-- Grant permissions on tables
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;

-- Grant permissions on sequences
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Grant execute on functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon;

-- =============================================================================
-- STEP 9: TEST THE SETUP
-- =============================================================================

-- Test function calls
SELECT 'Database setup complete!' as status;

-- Test user search
SELECT 'User search test:' as test, count(*) as user_count 
FROM public.get_searchable_users('john');

-- Test admin function
SELECT 'Admin test:' as test, public.is_admin('11111111-1111-1111-1111-111111111111') as is_admin_result;
