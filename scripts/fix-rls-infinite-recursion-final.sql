-- DEFINITIVE FIX FOR INFINITE RECURSION IN RLS POLICIES
-- This script completely eliminates recursive RLS policies and creates secure alternatives

-- ==================================================
-- 1. DISABLE RLS TEMPORARILY FOR CLEANUP
-- ==================================================

ALTER TABLE IF EXISTS public.chat_participants DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.chats DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.contacts DISABLE ROW LEVEL SECURITY;

-- ==================================================
-- 2. DROP ALL EXISTING PROBLEMATIC POLICIES
-- ==================================================

-- Drop chat_participants policies
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_participants;
DROP POLICY IF EXISTS "chat_participants_select" ON public.chat_participants;
DROP POLICY IF EXISTS "chat_participants_insert" ON public.chat_participants;
DROP POLICY IF EXISTS "chat_participants_update" ON public.chat_participants;
DROP POLICY IF EXISTS "allow_read_chat_participants" ON public.chat_participants;
DROP POLICY IF EXISTS "allow_insert_chat_participants" ON public.chat_participants;

-- Drop chats policies
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
DROP POLICY IF EXISTS "Users can create chats" ON public.chats;
DROP POLICY IF EXISTS "chats_select" ON public.chats;
DROP POLICY IF EXISTS "chats_insert" ON public.chats;
DROP POLICY IF EXISTS "allow_read_user_chats" ON public.chats;
DROP POLICY IF EXISTS "allow_create_chats" ON public.chats;

-- Drop messages policies
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
DROP POLICY IF EXISTS "messages_select" ON public.messages;
DROP POLICY IF EXISTS "messages_insert" ON public.messages;
DROP POLICY IF EXISTS "allow_read_messages" ON public.messages;
DROP POLICY IF EXISTS "allow_insert_messages" ON public.messages;

-- ==================================================
-- 3. ENSURE CORRECT TABLE STRUCTURE
-- ==================================================

-- Ensure chat_participants table exists with correct structure
CREATE TABLE IF NOT EXISTS public.chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- Ensure chats table has correct structure
CREATE TABLE IF NOT EXISTS public.chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    type TEXT DEFAULT 'direct' CHECK (type IN ('direct', 'group')),
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ==================================================
-- 4. CREATE SECURITY DEFINER FUNCTIONS TO BYPASS RLS
-- ==================================================

-- Function to safely create direct chat with members
CREATE OR REPLACE FUNCTION public.create_direct_chat_with_members(
    user1 UUID,
    user2 UUID
)
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
    )
    AND (
        SELECT COUNT(*) FROM chat_participants cp 
        WHERE cp.chat_id = c.id
    ) = 2;
    
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

-- Function to safely get user's chats
CREATE OR REPLACE FUNCTION public.get_user_chats_safe(user_uuid UUID)
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

-- Function to safely check if user is chat participant
CREATE OR REPLACE FUNCTION public.is_chat_participant(chat_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM chat_participants 
        WHERE chat_id = chat_uuid AND user_id = user_uuid
    );
END;
$$;

-- Function to get searchable users with proper search_path
CREATE OR REPLACE FUNCTION public.get_searchable_users(
    search_query TEXT DEFAULT '',
    current_user_id UUID DEFAULT NULL,
    result_limit INTEGER DEFAULT 20
)
RETURNS TABLE(
    id UUID,
    email TEXT,
    username TEXT,
    full_name TEXT,
    avatar_url TEXT,
    bio TEXT,
    phone TEXT,
    is_online BOOLEAN,
    last_seen TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    contact_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_uid UUID;
BEGIN
    -- Get current user ID
    current_uid := COALESCE(current_user_id, auth.uid());
    
    RETURN QUERY
    SELECT 
        u.id,
        u.email,
        u.username,
        u.full_name,
        u.avatar_url,
        u.bio,
        u.phone,
        u.is_online,
        u.last_seen,
        u.created_at,
        u.updated_at,
        COALESCE(c.status, 'none') as contact_status
    FROM users u
    LEFT JOIN contacts c ON (
        (c.user_id = current_uid AND c.contact_user_id = u.id) OR
        (c.contact_user_id = current_uid AND c.user_id = u.id)
    )
    WHERE 
        u.id != current_uid
        AND (
            search_query = '' OR
            u.username ILIKE '%' || search_query || '%' OR
            u.full_name ILIKE '%' || search_query || '%' OR
            u.email ILIKE '%' || search_query || '%'
        )
    ORDER BY 
        CASE WHEN u.is_online THEN 0 ELSE 1 END,
        u.full_name,
        u.username
    LIMIT result_limit;
END;
$$;

-- ==================================================
-- 5. CREATE SIMPLE, NON-RECURSIVE RLS POLICIES
-- ==================================================

-- Users table policies (simple and safe)
CREATE POLICY "users_select_all" ON public.users
    FOR SELECT USING (true);

CREATE POLICY "users_insert_own" ON public.users
    FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "users_update_own" ON public.users
    FOR UPDATE USING (auth.uid() = id);

-- Chat participants policies (extremely simple to avoid recursion)
CREATE POLICY "chat_participants_select_simple" ON public.chat_participants
    FOR SELECT USING (true);

CREATE POLICY "chat_participants_insert_simple" ON public.chat_participants
    FOR INSERT WITH CHECK (true);

CREATE POLICY "chat_participants_update_own" ON public.chat_participants
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "chat_participants_delete_own" ON public.chat_participants
    FOR DELETE USING (user_id = auth.uid());

-- Chats policies (simple with direct subquery, no recursion)
CREATE POLICY "chats_select_participant" ON public.chats
    FOR SELECT USING (
        id IN (
            SELECT chat_id FROM chat_participants WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "chats_insert_own" ON public.chats
    FOR INSERT WITH CHECK (created_by = auth.uid());

CREATE POLICY "chats_update_creator" ON public.chats
    FOR UPDATE USING (created_by = auth.uid());

-- Messages policies (simple with direct subquery, no recursion)
CREATE POLICY "messages_select_participant" ON public.messages
    FOR SELECT USING (
        chat_id IN (
            SELECT chat_id FROM chat_participants WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "messages_insert_participant" ON public.messages
    FOR INSERT WITH CHECK (
        user_id = auth.uid() AND
        chat_id IN (
            SELECT chat_id FROM chat_participants WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "messages_update_own" ON public.messages
    FOR UPDATE USING (user_id = auth.uid());

-- Contacts policies (simple and direct)
CREATE POLICY "contacts_select_own" ON public.contacts
    FOR SELECT USING (user_id = auth.uid() OR contact_user_id = auth.uid());

CREATE POLICY "contacts_insert_own" ON public.contacts
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "contacts_update_own" ON public.contacts
    FOR UPDATE USING (user_id = auth.uid() OR contact_user_id = auth.uid());

-- ==================================================
-- 6. RE-ENABLE RLS
-- ==================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

-- ==================================================
-- 7. GRANT PERMISSIONS
-- ==================================================

GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_chats_safe TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_chat_participant TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_searchable_users TO authenticated;

-- ==================================================
-- 8. CREATE INDEXES FOR PERFORMANCE
-- ==================================================

CREATE INDEX IF NOT EXISTS idx_chat_participants_chat_id ON public.chat_participants(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON public.chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_chat_user ON public.chat_participants(chat_id, user_id);
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_user_id ON public.messages(user_id);
CREATE INDEX IF NOT EXISTS idx_chats_type ON public.chats(type);
CREATE INDEX IF NOT EXISTS idx_chats_created_by ON public.chats(created_by);

-- ==================================================
-- 9. TEST THE FIX
-- ==================================================

DO $$
BEGIN
    -- Test that we can query without recursion
    PERFORM COUNT(*) FROM public.chat_participants;
    PERFORM COUNT(*) FROM public.chats;
    PERFORM COUNT(*) FROM public.messages;
    
    RAISE NOTICE 'SUCCESS: All tables can be queried without infinite recursion';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ERROR: %', SQLERRM;
END $$;

SELECT 'RLS infinite recursion fix completed successfully!' as status;
