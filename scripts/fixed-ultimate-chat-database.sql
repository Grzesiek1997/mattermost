-- ULTIMATE TELEGRAM CLONE DATABASE - FIXED VERSION
-- Comprehensive chat application with proper user roles and permissions
-- Fixed column order and dependencies

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================
-- STEP 1: DROP ALL EXISTING POLICIES FIRST
-- =============================================

-- Drop all existing policies to prevent conflicts
DROP POLICY IF EXISTS "Users can view all profiles" ON public.users;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can create chats" ON public.chats;
DROP POLICY IF EXISTS "Users can view chats they participate in" ON public.chats;
DROP POLICY IF EXISTS "Users can update chats they created" ON public.chats;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can leave chats" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
DROP POLICY IF EXISTS "Users can update their own messages" ON public.messages;
DROP POLICY IF EXISTS "Users can delete their own messages" ON public.messages;
DROP POLICY IF EXISTS "Users can manage their contacts" ON public.contacts;
DROP POLICY IF EXISTS "Users can view their contacts" ON public.contacts;
DROP POLICY IF EXISTS "Users can view notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update their notifications" ON public.notifications;

-- =============================================
-- STEP 2: CREATE ALL TABLES IN CORRECT ORDER
-- =============================================

-- Users table (base table, no dependencies)
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE,
    full_name TEXT,
    avatar_url TEXT,
    bio TEXT,
    phone TEXT,
    status TEXT DEFAULT 'offline',
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_online BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Roles table (for RBAC system)
CREATE TABLE IF NOT EXISTS public.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    description TEXT,
    level INTEGER DEFAULT 0, -- 0=user, 10=moderator, 50=admin, 100=super_admin
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Permissions table
CREATE TABLE IF NOT EXISTS public.permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    description TEXT,
    resource TEXT NOT NULL, -- table or feature name
    action TEXT NOT NULL, -- SELECT, INSERT, UPDATE, DELETE, MANAGE
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Role permissions mapping
CREATE TABLE IF NOT EXISTS public.role_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID REFERENCES public.roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES public.permissions(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(role_id, permission_id)
);

-- User roles mapping
CREATE TABLE IF NOT EXISTS public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role_id UUID REFERENCES public.roles(id) ON DELETE CASCADE,
    assigned_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true,
    UNIQUE(user_id, role_id)
);

-- Chats table (NOW with is_public column properly defined)
CREATE TABLE IF NOT EXISTS public.chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    description TEXT,
    type TEXT NOT NULL DEFAULT 'direct', -- 'direct', 'group', 'channel', 'broadcast'
    is_group BOOLEAN DEFAULT false,
    is_direct BOOLEAN DEFAULT true,
    is_public BOOLEAN DEFAULT false, -- <-- THIS IS THE COLUMN CAUSING THE ERROR
    avatar_url TEXT,
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    max_members INTEGER DEFAULT 200,
    invite_link TEXT UNIQUE,
    settings JSONB DEFAULT '{"allow_media": true, "allow_links": true, "slow_mode": false, "message_history": true}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Chat participants table
CREATE TABLE IF NOT EXISTS public.chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member', -- 'owner', 'admin', 'moderator', 'member'
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    left_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true,
    permissions JSONB DEFAULT '{"can_send_messages": true, "can_add_members": false, "can_delete_messages": false}',
    UNIQUE(chat_id, user_id)
);

-- Messages table
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT,
    message_type TEXT DEFAULT 'text', -- 'text', 'image', 'file', 'voice', 'video', 'system'
    file_url TEXT,
    file_name TEXT,
    file_size INTEGER,
    reply_to UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    forwarded_from UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    is_edited BOOLEAN DEFAULT false,
    is_deleted BOOLEAN DEFAULT false,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Contacts table
CREATE TABLE IF NOT EXISTS public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending', -- 'pending', 'accepted', 'blocked', 'rejected'
    invited_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    invited_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    accepted_at TIMESTAMP WITH TIME ZONE,
    blocked_at TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    UNIQUE(user_id, contact_id)
);

-- Notifications table
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL, -- 'contact_request', 'message', 'chat_invite', 'system'
    title TEXT NOT NULL,
    message TEXT,
    data JSONB DEFAULT '{}',
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE
);

-- Additional advanced tables for full messenger functionality
CREATE TABLE IF NOT EXISTS public.message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id, emoji)
);

CREATE TABLE IF NOT EXISTS public.message_reads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.typing_indicators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    is_typing BOOLEAN DEFAULT true,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.chat_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    invited_by UUID REFERENCES public.users(id) ON DELETE CASCADE,
    invited_user UUID REFERENCES public.users(id) ON DELETE CASCADE,
    invite_code TEXT UNIQUE,
    status TEXT DEFAULT 'pending', -- 'pending', 'accepted', 'rejected', 'expired'
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, invited_user)
);

-- =============================================
-- STEP 3: INSERT DEFAULT ROLES AND PERMISSIONS
-- =============================================

-- Insert default roles
INSERT INTO public.roles (name, display_name, description, level) VALUES
('super_admin', 'Super Administrator', 'Full system access', 100),
('admin', 'Administrator', 'Administrative access', 50),
('moderator', 'Moderator', 'Content moderation access', 10),
('user', 'User', 'Standard user access', 0),
('guest', 'Guest', 'Limited guest access', -10)
ON CONFLICT (name) DO NOTHING;

-- Insert default permissions
INSERT INTO public.permissions (name, display_name, description, resource, action) VALUES
('users.read', 'Read Users', 'View user profiles', 'users', 'SELECT'),
('users.write', 'Write Users', 'Create/update user profiles', 'users', 'INSERT'),
('users.update', 'Update Users', 'Update user profiles', 'users', 'UPDATE'),
('users.delete', 'Delete Users', 'Delete user profiles', 'users', 'DELETE'),
('chats.read', 'Read Chats', 'View chats', 'chats', 'SELECT'),
('chats.write', 'Write Chats', 'Create chats', 'chats', 'INSERT'),
('chats.update', 'Update Chats', 'Update chats', 'chats', 'UPDATE'),
('chats.delete', 'Delete Chats', 'Delete chats', 'chats', 'DELETE'),
('messages.read', 'Read Messages', 'View messages', 'messages', 'SELECT'),
('messages.write', 'Write Messages', 'Send messages', 'messages', 'INSERT'),
('messages.update', 'Update Messages', 'Edit messages', 'messages', 'UPDATE'),
('messages.delete', 'Delete Messages', 'Delete messages', 'messages', 'DELETE'),
('admin.manage', 'Admin Management', 'Full administrative access', 'system', 'MANAGE')
ON CONFLICT (name) DO NOTHING;

-- =============================================
-- STEP 4: CREATE INDEXES FOR PERFORMANCE
-- =============================================

-- Users indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON public.users(username);
CREATE INDEX IF NOT EXISTS idx_users_status ON public.users(status);
CREATE INDEX IF NOT EXISTS idx_users_is_online ON public.users(is_online);

-- Chats indexes
CREATE INDEX IF NOT EXISTS idx_chats_type ON public.chats(type);
CREATE INDEX IF NOT EXISTS idx_chats_created_by ON public.chats(created_by);
CREATE INDEX IF NOT EXISTS idx_chats_is_public ON public.chats(is_public);

-- Chat participants indexes
CREATE INDEX IF NOT EXISTS idx_chat_participants_chat_id ON public.chat_participants(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON public.chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_role ON public.chat_participants(role);

-- Messages indexes
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_user_id ON public.messages(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at);
CREATE INDEX IF NOT EXISTS idx_messages_type ON public.messages(message_type);

-- Contacts indexes
CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON public.contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_contact_id ON public.contacts(contact_id);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON public.contacts(status);

-- Notifications indexes
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON public.notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(is_read);

-- =============================================
-- STEP 5: ENABLE RLS ON ALL TABLES
-- =============================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_invites ENABLE ROW LEVEL SECURITY;

-- =============================================
-- STEP 6: CREATE SIMPLE, NON-RECURSIVE RLS POLICIES
-- =============================================

-- Users policies
CREATE POLICY "Users can view all profiles" ON public.users
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "Users can insert their own profile" ON public.users
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON public.users
    FOR UPDATE TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Chats policies (FIXED - now is_public column exists)
CREATE POLICY "Users can view public chats" ON public.chats
    FOR SELECT TO authenticated
    USING (is_public = true OR id IN (
        SELECT chat_id FROM public.chat_participants 
        WHERE user_id = auth.uid() AND is_active = true
    ));

CREATE POLICY "Users can create chats" ON public.chats
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Chat creators can update their chats" ON public.chats
    FOR UPDATE TO authenticated
    USING (auth.uid() = created_by)
    WITH CHECK (auth.uid() = created_by);

-- Chat participants policies
CREATE POLICY "Users can view chat participants" ON public.chat_participants
    FOR SELECT TO authenticated
    USING (chat_id IN (
        SELECT chat_id FROM public.chat_participants 
        WHERE user_id = auth.uid() AND is_active = true
    ));

CREATE POLICY "Users can join chats" ON public.chat_participants
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can leave chats" ON public.chat_participants
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Messages policies
CREATE POLICY "Users can view messages in their chats" ON public.messages
    FOR SELECT TO authenticated
    USING (chat_id IN (
        SELECT chat_id FROM public.chat_participants 
        WHERE user_id = auth.uid() AND is_active = true
    ));

CREATE POLICY "Users can send messages" ON public.messages
    FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid() = user_id AND 
        chat_id IN (
            SELECT chat_id FROM public.chat_participants 
            WHERE user_id = auth.uid() AND is_active = true
        )
    );

CREATE POLICY "Users can update their own messages" ON public.messages
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own messages" ON public.messages
    FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- Contacts policies
CREATE POLICY "Users can manage their contacts" ON public.contacts
    FOR ALL TO authenticated
    USING (auth.uid() = user_id OR auth.uid() = contact_id)
    WITH CHECK (auth.uid() = user_id OR auth.uid() = contact_id);

-- Notifications policies
CREATE POLICY "Users can view their notifications" ON public.notifications
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their notifications" ON public.notifications
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- =============================================
-- STEP 7: CREATE SECURITY DEFINER FUNCTIONS
-- =============================================

-- Function to check if user is admin
CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.user_roles ur
        JOIN public.roles r ON ur.role_id = r.id
        WHERE ur.user_id = user_uuid 
        AND r.name IN ('admin', 'super_admin')
        AND ur.is_active = true
    );
END;
$$;

-- Function to get user role
CREATE OR REPLACE FUNCTION public.get_user_role(user_uuid UUID DEFAULT auth.uid())
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_role TEXT;
BEGIN
    SELECT r.name INTO user_role
    FROM public.user_roles ur
    JOIN public.roles r ON ur.role_id = r.id
    WHERE ur.user_id = user_uuid 
    AND ur.is_active = true
    ORDER BY r.level DESC
    LIMIT 1;
    
    RETURN COALESCE(user_role, 'user');
END;
$$;

-- Function to search users
CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term TEXT DEFAULT '')
RETURNS TABLE (
    id UUID,
    username TEXT,
    full_name TEXT,
    avatar_url TEXT,
    status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, u.username, u.full_name, u.avatar_url, u.status
    FROM public.users u
    WHERE u.id != auth.uid()
    AND (
        search_term = '' OR
        u.username ILIKE '%' || search_term || '%' OR
        u.full_name ILIKE '%' || search_term || '%'
    )
    ORDER BY u.full_name, u.username
    LIMIT 50;
END;
$$;

-- Function to create direct chat
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
        WHERE cp1.chat_id = c.id AND cp1.user_id = user1 AND cp1.is_active = true
    )
    AND EXISTS (
        SELECT 1 FROM public.chat_participants cp2 
        WHERE cp2.chat_id = c.id AND cp2.user_id = user2 AND cp2.is_active = true
    );
    
    IF existing_chat_id IS NOT NULL THEN
        RETURN existing_chat_id;
    END IF;
    
    -- Create new direct chat
    INSERT INTO public.chats (type, is_direct, is_group, created_by)
    VALUES ('direct', true, false, user1)
    RETURNING id INTO chat_id;
    
    -- Add both users as participants
    INSERT INTO public.chat_participants (chat_id, user_id, role)
    VALUES 
        (chat_id, user1, 'member'),
        (chat_id, user2, 'member');
    
    RETURN chat_id;
END;
$$;

-- =============================================
-- STEP 8: CREATE TEST DATA
-- =============================================

-- Insert test users
INSERT INTO public.users (id, email, username, full_name, avatar_url) VALUES
('11111111-1111-1111-1111-111111111111', 'john@example.com', 'john_doe', 'John Doe', '/placeholder.svg?height=40&width=40'),
('22222222-2222-2222-2222-222222222222', 'jane@example.com', 'jane_smith', 'Jane Smith', '/placeholder.svg?height=40&width=40'),
('33333333-3333-3333-3333-333333333333', 'test@example.com', 'test_user', 'Test User', '/placeholder.svg?height=40&width=40')
ON CONFLICT (email) DO NOTHING;

-- Assign default user role to test users
INSERT INTO public.user_roles (user_id, role_id)
SELECT u.id, r.id
FROM public.users u
CROSS JOIN public.roles r
WHERE r.name = 'user'
AND u.email IN ('john@example.com', 'jane@example.com', 'test@example.com')
ON CONFLICT (user_id, role_id) DO NOTHING;

-- Create a super admin user (first user becomes super admin)
INSERT INTO public.user_roles (user_id, role_id)
SELECT u.id, r.id
FROM public.users u
CROSS JOIN public.roles r
WHERE r.name = 'super_admin'
AND u.email = 'john@example.com'
ON CONFLICT (user_id, role_id) DO NOTHING;

SELECT 'Ultimate Telegram Clone Database Setup Complete!' as status;
