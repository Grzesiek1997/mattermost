-- ULTIMATE TELEGRAM CLONE DATABASE SETUP
-- Based on Supabase best practices for chat applications
-- Includes all possible features and optimizations

-- =============================================================================
-- STEP 1: CLEAN EXISTING POLICIES AND FUNCTIONS
-- =============================================================================

-- Drop all existing policies to prevent conflicts
DROP POLICY IF EXISTS "Users can view all profiles" ON public.users;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can create chats" ON public.chats;
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
DROP POLICY IF EXISTS "Users can update their chats" ON public.chats;
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can leave chats" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
DROP POLICY IF EXISTS "Users can update their messages" ON public.messages;
DROP POLICY IF EXISTS "Users can delete their messages" ON public.messages;
DROP POLICY IF EXISTS "Users can view their contacts" ON public.contacts;
DROP POLICY IF EXISTS "Users can manage their contacts" ON public.contacts;
DROP POLICY IF EXISTS "Users can update their contacts" ON public.contacts;

-- Drop existing functions
DROP FUNCTION IF EXISTS public.get_searchable_users(text) CASCADE;
DROP FUNCTION IF EXISTS public.create_direct_chat_with_members(uuid, uuid) CASCADE;
DROP FUNCTION IF EXISTS public.is_admin(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_admin_role(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.create_first_super_admin(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.promote_user_to_admin(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.get_user_chats_secure(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.send_message_secure(uuid, text, text) CASCADE;

-- =============================================================================
-- STEP 2: CREATE COMPREHENSIVE TABLE STRUCTURE
-- =============================================================================

-- Users table with all possible fields
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
    status TEXT DEFAULT 'active', -- active, inactive, banned
    language TEXT DEFAULT 'en',
    timezone TEXT DEFAULT 'UTC',
    theme TEXT DEFAULT 'light', -- light, dark, auto
    notification_settings JSONB DEFAULT '{"messages": true, "calls": true, "groups": true}',
    privacy_settings JSONB DEFAULT '{"last_seen": "everyone", "profile_photo": "everyone", "status": "everyone"}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Chats table with comprehensive features
CREATE TABLE IF NOT EXISTS public.chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    description TEXT,
    type TEXT NOT NULL DEFAULT 'direct', -- direct, group, channel, broadcast
    is_group BOOLEAN DEFAULT false,
    is_direct BOOLEAN DEFAULT true,
    avatar_url TEXT,
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    max_members INTEGER DEFAULT 200,
    is_public BOOLEAN DEFAULT false,
    invite_link TEXT,
    settings JSONB DEFAULT '{"allow_media": true, "allow_links": true, "slow_mode": false}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Chat participants with roles and permissions
CREATE TABLE IF NOT EXISTS public.chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member', -- owner, admin, moderator, member
    permissions JSONB DEFAULT '{"can_send_messages": true, "can_add_members": false, "can_delete_messages": false}',
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    invited_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    is_muted BOOLEAN DEFAULT false,
    muted_until TIMESTAMP WITH TIME ZONE,
    UNIQUE(chat_id, user_id)
);

-- Messages with all features
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text', -- text, image, video, audio, file, location, contact
    reply_to UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    forward_from UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    edited_at TIMESTAMP WITH TIME ZONE,
    is_deleted BOOLEAN DEFAULT false,
    is_pinned BOOLEAN DEFAULT false,
    metadata JSONB DEFAULT '{}', -- file info, location data, etc.
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Message reactions
CREATE TABLE IF NOT EXISTS public.message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id, emoji)
);

-- Message reads/delivery status
CREATE TABLE IF NOT EXISTS public.message_reads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id)
);

-- Contacts with comprehensive status tracking
CREATE TABLE IF NOT EXISTS public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending', -- pending, accepted, blocked, declined
    nickname TEXT, -- custom name for contact
    is_favorite BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    accepted_at TIMESTAMP WITH TIME ZONE,
    blocked_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, contact_user_id)
);

-- Notifications system
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL, -- message, contact_request, group_invite, etc.
    title TEXT NOT NULL,
    content TEXT,
    data JSONB DEFAULT '{}',
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Typing indicators
CREATE TABLE IF NOT EXISTS public.typing_indicators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    is_typing BOOLEAN DEFAULT true,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- File uploads
CREATE TABLE IF NOT EXISTS public.file_uploads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    filename TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_size BIGINT,
    mime_type TEXT,
    is_public BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Admin system
CREATE TABLE IF NOT EXISTS public.admin_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
    role TEXT NOT NULL DEFAULT 'admin', -- super_admin, admin, moderator
    permissions JSONB DEFAULT '{}',
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Admin actions log
CREATE TABLE IF NOT EXISTS public.admin_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID REFERENCES public.admin_users(user_id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    target_type TEXT, -- user, chat, message
    target_id UUID,
    details JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- System settings
CREATE TABLE IF NOT EXISTS public.system_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT UNIQUE NOT NULL,
    value JSONB NOT NULL,
    description TEXT,
    updated_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- User reports
CREATE TABLE IF NOT EXISTS public.user_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    reported_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    reported_message_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    reason TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'pending', -- pending, reviewed, resolved, dismissed
    reviewed_by UUID REFERENCES public.admin_users(user_id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    reviewed_at TIMESTAMP WITH TIME ZONE
);

-- =============================================================================
-- STEP 3: CREATE PERFORMANCE INDEXES
-- =============================================================================

-- Users indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON public.users(username);
CREATE INDEX IF NOT EXISTS idx_users_is_online ON public.users(is_online);
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON public.users(last_seen);

-- Chats indexes
CREATE INDEX IF NOT EXISTS idx_chats_created_by ON public.chats(created_by);
CREATE INDEX IF NOT EXISTS idx_chats_type ON public.chats(type);
CREATE INDEX IF NOT EXISTS idx_chats_is_public ON public.chats(is_public);

-- Chat participants indexes
CREATE INDEX IF NOT EXISTS idx_chat_participants_chat_id ON public.chat_participants(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON public.chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_role ON public.chat_participants(role);

-- Messages indexes
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_user_id ON public.messages(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at);
CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON public.messages(reply_to);

-- Contacts indexes
CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON public.contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_contact_user_id ON public.contacts(contact_user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON public.contacts(status);

-- Notifications indexes
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at);

-- =============================================================================
-- STEP 4: ENABLE ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.file_uploads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- STEP 5: CREATE OPTIMIZED RLS POLICIES
-- =============================================================================

-- Users policies (optimized with TO clauses)
CREATE POLICY "Users can view all profiles" ON public.users
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "Users can insert their own profile" ON public.users
    FOR INSERT TO authenticated
    WITH CHECK ((SELECT auth.uid()) = id);

CREATE POLICY "Users can update their own profile" ON public.users
    FOR UPDATE TO authenticated
    USING ((SELECT auth.uid()) = id)
    WITH CHECK ((SELECT auth.uid()) = id);

-- Chats policies (simple, non-recursive)
CREATE POLICY "Users can create chats" ON public.chats
    FOR INSERT TO authenticated
    WITH CHECK ((SELECT auth.uid()) = created_by);

CREATE POLICY "Users can view their chats" ON public.chats
    FOR SELECT TO authenticated
    USING (
        id IN (
            SELECT chat_id FROM public.chat_participants 
            WHERE user_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Users can update their chats" ON public.chats
    FOR UPDATE TO authenticated
    USING ((SELECT auth.uid()) = created_by)
    WITH CHECK ((SELECT auth.uid()) = created_by);

-- Chat participants policies (optimized)
CREATE POLICY "Users can view chat participants" ON public.chat_participants
    FOR SELECT TO authenticated
    USING (
        chat_id IN (
            SELECT chat_id FROM public.chat_participants 
            WHERE user_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Users can join chats" ON public.chat_participants
    FOR INSERT TO authenticated
    WITH CHECK (
        user_id = (SELECT auth.uid()) OR
        chat_id IN (
            SELECT chat_id FROM public.chat_participants 
            WHERE user_id = (SELECT auth.uid()) AND role IN ('owner', 'admin')
        )
    );

CREATE POLICY "Users can leave chats" ON public.chat_participants
    FOR DELETE TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR
        chat_id IN (
            SELECT chat_id FROM public.chat_participants 
            WHERE user_id = (SELECT auth.uid()) AND role IN ('owner', 'admin')
        )
    );

-- Messages policies (performance optimized)
CREATE POLICY "Users can view messages in their chats" ON public.messages
    FOR SELECT TO authenticated
    USING (
        chat_id IN (
            SELECT chat_id FROM public.chat_participants 
            WHERE user_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Users can send messages" ON public.messages
    FOR INSERT TO authenticated
    WITH CHECK (
        user_id = (SELECT auth.uid()) AND
        chat_id IN (
            SELECT chat_id FROM public.chat_participants 
            WHERE user_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Users can update their messages" ON public.messages
    FOR UPDATE TO authenticated
    USING (user_id = (SELECT auth.uid()))
    WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can delete their messages" ON public.messages
    FOR DELETE TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR
        chat_id IN (
            SELECT chat_id FROM public.chat_participants 
            WHERE user_id = (SELECT auth.uid()) AND role IN ('owner', 'admin', 'moderator')
        )
    );

-- Message reactions policies
CREATE POLICY "Users can view reactions" ON public.message_reactions
    FOR SELECT TO authenticated
    USING (
        message_id IN (
            SELECT id FROM public.messages 
            WHERE chat_id IN (
                SELECT chat_id FROM public.chat_participants 
                WHERE user_id = (SELECT auth.uid())
            )
        )
    );

CREATE POLICY "Users can add reactions" ON public.message_reactions
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can remove their reactions" ON public.message_reactions
    FOR DELETE TO authenticated
    USING (user_id = (SELECT auth.uid()));

-- Message reads policies
CREATE POLICY "Users can view message reads" ON public.message_reads
    FOR SELECT TO authenticated
    USING (
        message_id IN (
            SELECT id FROM public.messages 
            WHERE chat_id IN (
                SELECT chat_id FROM public.chat_participants 
                WHERE user_id = (SELECT auth.uid())
            )
        )
    );

CREATE POLICY "Users can mark messages as read" ON public.message_reads
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()));

-- Contacts policies
CREATE POLICY "Users can view their contacts" ON public.contacts
    FOR SELECT TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR 
        contact_user_id = (SELECT auth.uid())
    );

CREATE POLICY "Users can manage their contacts" ON public.contacts
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can update their contacts" ON public.contacts
    FOR UPDATE TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR 
        contact_user_id = (SELECT auth.uid())
    )
    WITH CHECK (
        user_id = (SELECT auth.uid()) OR 
        contact_user_id = (SELECT auth.uid())
    );

-- Notifications policies
CREATE POLICY "Users can view their notifications" ON public.notifications
    FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can update their notifications" ON public.notifications
    FOR UPDATE TO authenticated
    USING (user_id = (SELECT auth.uid()))
    WITH CHECK (user_id = (SELECT auth.uid()));

-- Typing indicators policies
CREATE POLICY "Users can view typing indicators" ON public.typing_indicators
    FOR SELECT TO authenticated
    USING (
        chat_id IN (
            SELECT chat_id FROM public.chat_participants 
            WHERE user_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Users can manage their typing status" ON public.typing_indicators
    FOR ALL TO authenticated
    USING (user_id = (SELECT auth.uid()))
    WITH CHECK (user_id = (SELECT auth.uid()));

-- File uploads policies
CREATE POLICY "Users can view accessible files" ON public.file_uploads
    FOR SELECT TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR 
        is_public = true
    );

CREATE POLICY "Users can upload files" ON public.file_uploads
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()));

-- Admin policies
CREATE POLICY "Admins can view admin users" ON public.admin_users
    FOR SELECT TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR
        (SELECT auth.uid()) IN (SELECT user_id FROM public.admin_users)
    );

CREATE POLICY "Super admins can manage admins" ON public.admin_users
    FOR ALL TO authenticated
    USING (
        (SELECT auth.uid()) IN (
            SELECT user_id FROM public.admin_users WHERE role = 'super_admin'
        )
    );

CREATE POLICY "Admins can view actions" ON public.admin_actions
    FOR SELECT TO authenticated
    USING (
        (SELECT auth.uid()) IN (SELECT user_id FROM public.admin_users)
    );

CREATE POLICY "Admins can log actions" ON public.admin_actions
    FOR INSERT TO authenticated
    WITH CHECK (
        admin_user_id = (SELECT auth.uid()) AND
        (SELECT auth.uid()) IN (SELECT user_id FROM public.admin_users)
    );

-- System settings policies
CREATE POLICY "Admins can view settings" ON public.system_settings
    FOR SELECT TO authenticated
    USING (
        (SELECT auth.uid()) IN (SELECT user_id FROM public.admin_users)
    );

CREATE POLICY "Super admins can manage settings" ON public.system_settings
    FOR ALL TO authenticated
    USING (
        (SELECT auth.uid()) IN (
            SELECT user_id FROM public.admin_users WHERE role = 'super_admin'
        )
    );

-- User reports policies
CREATE POLICY "Users can create reports" ON public.user_reports
    FOR INSERT TO authenticated
    WITH CHECK (reporter_id = (SELECT auth.uid()));

CREATE POLICY "Admins can view reports" ON public.user_reports
    FOR SELECT TO authenticated
    USING (
        reporter_id = (SELECT auth.uid()) OR
        (SELECT auth.uid()) IN (SELECT user_id FROM public.admin_users)
    );

CREATE POLICY "Admins can update reports" ON public.user_reports
    FOR UPDATE TO authenticated
    USING (
        (SELECT auth.uid()) IN (SELECT user_id FROM public.admin_users)
    );

-- =============================================================================
-- STEP 6: CREATE SECURITY DEFINER FUNCTIONS
-- =============================================================================

-- Function to search users (bypasses RLS for performance)
CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term text)
RETURNS TABLE(
    id uuid,
    username text,
    full_name text,
    avatar_url text,
    is_online boolean
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
        u.is_online
    FROM public.users u
    WHERE 
        u.id != auth.uid() AND
        u.status = 'active' AND
        (
            u.username ILIKE '%' || search_term || '%' OR
            u.full_name ILIKE '%' || search_term || '%'
        )
    ORDER BY u.username
    LIMIT 20;
END;
$$;

-- Function to create direct chat with members (bypasses RLS)
CREATE OR REPLACE FUNCTION public.create_direct_chat_with_members(user1 uuid, user2 uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    chat_id uuid;
    existing_chat_id uuid;
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

-- Function to get user chats (bypasses RLS for performance)
CREATE OR REPLACE FUNCTION public.get_user_chats_secure(user_uuid uuid)
RETURNS TABLE(
    id uuid,
    name text,
    type text,
    is_group boolean,
    avatar_url text,
    created_at timestamptz,
    last_message_content text,
    last_message_created_at timestamptz,
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
        CASE 
            WHEN c.type = 'direct' THEN (
                SELECT u.full_name 
                FROM public.users u 
                JOIN public.chat_participants cp ON cp.user_id = u.id 
                WHERE cp.chat_id = c.id AND cp.user_id != user_uuid 
                LIMIT 1
            )
            ELSE c.name
        END as name,
        c.type,
        c.is_group,
        c.avatar_url,
        c.created_at,
        (
            SELECT m.content 
            FROM public.messages m 
            WHERE m.chat_id = c.id 
            ORDER BY m.created_at DESC 
            LIMIT 1
        ) as last_message_content,
        (
            SELECT m.created_at 
            FROM public.messages m 
            WHERE m.chat_id = c.id 
            ORDER BY m.created_at DESC 
            LIMIT 1
        ) as last_message_created_at,
        (
            SELECT COUNT(*)
            FROM public.messages m
            WHERE m.chat_id = c.id
            AND m.id NOT IN (
                SELECT mr.message_id 
                FROM public.message_reads mr 
                WHERE mr.user_id = user_uuid
            )
        ) as unread_count
    FROM public.chats c
    JOIN public.chat_participants cp ON cp.chat_id = c.id
    WHERE cp.user_id = user_uuid
    ORDER BY (
        SELECT m.created_at 
        FROM public.messages m 
        WHERE m.chat_id = c.id 
        ORDER BY m.created_at DESC 
        LIMIT 1
    ) DESC NULLS LAST;
END;
$$;

-- Admin functions
CREATE OR REPLACE FUNCTION public.is_admin(user_uuid uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_users 
        WHERE user_id = user_uuid
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_admin_role(user_uuid uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_role text;
BEGIN
    SELECT role INTO user_role
    FROM public.admin_users
    WHERE user_id = user_uuid;
    
    RETURN COALESCE(user_role, 'user');
END;
$$;

CREATE OR REPLACE FUNCTION public.create_first_super_admin(user_uuid uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    admin_count integer;
BEGIN
    -- Check if any super admin exists
    SELECT COUNT(*) INTO admin_count
    FROM public.admin_users
    WHERE role = 'super_admin';
    
    -- If no super admin exists, create one
    IF admin_count = 0 THEN
        INSERT INTO public.admin_users (user_id, role, created_by)
        VALUES (user_uuid, 'super_admin', user_uuid)
        ON CONFLICT (user_id) DO UPDATE SET role = 'super_admin';
        
        RETURN true;
    END IF;
    
    RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.promote_user_to_admin(user_uuid uuid, admin_role text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only super admins can promote users
    IF NOT EXISTS (
        SELECT 1 FROM public.admin_users 
        WHERE user_id = auth.uid() AND role = 'super_admin'
    ) THEN
        RETURN false;
    END IF;
    
    INSERT INTO public.admin_users (user_id, role, created_by)
    VALUES (user_uuid, admin_role, auth.uid())
    ON CONFLICT (user_id) DO UPDATE SET 
        role = admin_role,
        created_by = auth.uid();
    
    RETURN true;
END;
$$;

-- =============================================================================
-- STEP 7: CREATE TRIGGERS AND FUNCTIONS
-- =============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Add updated_at triggers
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_chats_updated_at BEFORE UPDATE ON public.chats
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_messages_updated_at BEFORE UPDATE ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_contacts_updated_at BEFORE UPDATE ON public.contacts
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Function to create user profile on signup
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
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1))
    );
    
    -- Create first super admin if none exists
    PERFORM public.create_first_super_admin(NEW.id);
    
    RETURN NEW;
END;
$$;

-- Trigger for new user signup
CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to send notification
CREATE OR REPLACE FUNCTION public.send_notification(
    recipient_id uuid,
    notification_type text,
    title text,
    content text DEFAULT NULL,
    data jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    notification_id uuid;
BEGIN
    INSERT INTO public.notifications (user_id, type, title, content, data)
    VALUES (recipient_id, notification_type, title, content, data)
    RETURNING id INTO notification_id;
    
    RETURN notification_id;
END;
$$;

-- =============================================================================
-- STEP 8: GRANT PERMISSIONS
-- =============================================================================

-- Grant execute permissions on functions
GRANT EXECUTE ON FUNCTION public.get_searchable_users TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_chats_secure TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_role TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_first_super_admin TO authenticated;
GRANT EXECUTE ON FUNCTION public.promote_user_to_admin TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_notification TO authenticated;

-- Grant usage on sequences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- =============================================================================
-- STEP 9: INSERT TEST DATA
-- =============================================================================

-- Insert test users (only if they don't exist)
INSERT INTO public.users (id, email, username, full_name, bio, is_online)
VALUES 
    ('11111111-1111-1111-1111-111111111111', 'john@example.com', 'john', 'John Doe', 'Test user for development', true),
    ('22222222-2222-2222-2222-222222222222', 'jane@example.com', 'jane', 'Jane Smith', 'Another test user', false),
    ('33333333-3333-3333-3333-333333333333', 'test@example.com', 'test', 'Test User', 'Testing account', true)
ON CONFLICT (id) DO NOTHING;

-- Insert system settings
INSERT INTO public.system_settings (key, value, description)
VALUES 
    ('max_file_size', '50000000', 'Maximum file upload size in bytes'),
    ('allowed_file_types', '["image/jpeg", "image/png", "image/gif", "video/mp4", "audio/mpeg"]', 'Allowed file MIME types'),
    ('max_group_members', '200', 'Maximum members per group chat'),
    ('message_retention_days', '365', 'Days to keep messages before archiving')
ON CONFLICT (key) DO UPDATE SET 
    value = EXCLUDED.value,
    updated_at = NOW();

-- =============================================================================
-- STEP 10: ENABLE REALTIME
-- =============================================================================

-- Enable realtime for tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.typing_indicators;
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reactions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.users;

-- =============================================================================
-- FINAL SUCCESS MESSAGE
-- =============================================================================

SELECT 'Ultimate Telegram Clone database setup completed successfully! 🚀' as status;
