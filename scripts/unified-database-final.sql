-- ==================================================
-- OSTATECZNA NAPRAWA BAZY DANYCH - TELEGRAM CLONE
-- ==================================================

-- Wyczyść istniejące funkcje żeby uniknąć duplikatów
DROP FUNCTION IF EXISTS public.get_searchable_users(text, uuid, integer);
DROP FUNCTION IF EXISTS public.get_searchable_users(text);
DROP FUNCTION IF EXISTS public.create_direct_chat_with_members(uuid);
DROP FUNCTION IF EXISTS public.create_group_chat(text, text, uuid[]);

-- ==================================================
-- 1. STRUKTURA TABEL (UJEDNOLICONA)
-- ==================================================

-- Upewnij się że wszystkie tabele istnieją z poprawną strukturą
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT auth.uid(),
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE NOT NULL,
    full_name TEXT,
    bio TEXT,
    avatar_url TEXT,
    phone TEXT,
    is_online BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    banned_at TIMESTAMP WITH TIME ZONE,
    banned_by UUID REFERENCES public.users(id),
    ban_until TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by UUID REFERENCES public.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    description TEXT,
    type TEXT DEFAULT 'direct' CHECK (type IN ('direct', 'group')),
    is_group BOOLEAN DEFAULT false,
    avatar_url TEXT,
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Używamy TYLKO chat_participants (nie chat_members)
CREATE TABLE IF NOT EXISTS public.chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'file', 'voice', 'video')),
    reply_to_message_id UUID REFERENCES public.messages(id),
    is_deleted BOOLEAN DEFAULT false,
    deleted_by UUID REFERENCES public.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'blocked')),
    is_blocked BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, contact_user_id)
);

-- Dodatkowe tabele dla pełnej funkcjonalności
CREATE TABLE IF NOT EXISTS public.message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id, emoji)
);

CREATE TABLE IF NOT EXISTS public.typing_indicators (
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY(chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID REFERENCES public.users(id),
    content_type TEXT NOT NULL CHECK (content_type IN ('message', 'user', 'chat')),
    content_id UUID NOT NULL,
    reason TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'dismissed')),
    resolved_by UUID REFERENCES public.users(id),
    resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.admin_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) UNIQUE,
    role TEXT NOT NULL CHECK (role IN ('moderator', 'admin', 'super_admin')),
    granted_by UUID REFERENCES public.users(id),
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.admin_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID REFERENCES public.users(id),
    action_type TEXT NOT NULL,
    target_type TEXT NOT NULL,
    target_id UUID NOT NULL,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ==================================================
-- 2. INDEKSY DLA WYDAJNOŚCI
-- ==================================================

CREATE INDEX IF NOT EXISTS idx_users_username ON public.users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_is_online ON public.users(is_online);
CREATE INDEX IF NOT EXISTS idx_chat_participants_chat_id ON public.chat_participants(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON public.chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON public.messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at);
CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON public.contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON public.contacts(status);

-- ==================================================
-- 3. PROSTE POLITYKI RLS (BEZ REKURENCJI)
-- ==================================================

-- Wyłącz RLS tymczasowo
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts DISABLE ROW LEVEL SECURITY;

-- Usuń wszystkie istniejące polityki
DROP POLICY IF EXISTS "Users can view all profiles" ON public.users;
DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
DROP POLICY IF EXISTS "Users can create chats" ON public.chats;
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can view messages" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
DROP POLICY IF EXISTS "Users can view contacts" ON public.contacts;
DROP POLICY IF EXISTS "Users can manage contacts" ON public.contacts;

-- Włącz RLS z nowymi politykami
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

-- PROSTE POLITYKI BEZ REKURENCJI
CREATE POLICY "users_select" ON public.users FOR SELECT USING (true);
CREATE POLICY "users_insert" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "users_update" ON public.users FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "chats_select" ON public.chats FOR SELECT USING (true);
CREATE POLICY "chats_insert" ON public.chats FOR INSERT WITH CHECK (auth.uid() = created_by);
CREATE POLICY "chats_update" ON public.chats FOR UPDATE USING (auth.uid() = created_by);

CREATE POLICY "chat_participants_select" ON public.chat_participants FOR SELECT USING (true);
CREATE POLICY "chat_participants_insert" ON public.chat_participants FOR INSERT WITH CHECK (true);
CREATE POLICY "chat_participants_update" ON public.chat_participants FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "messages_select" ON public.messages FOR SELECT USING (true);
CREATE POLICY "messages_insert" ON public.messages FOR INSERT WITH CHECK (auth.uid() = sender_id);
CREATE POLICY "messages_update" ON public.messages FOR UPDATE USING (auth.uid() = sender_id);

CREATE POLICY "contacts_select" ON public.contacts FOR SELECT USING (user_id = auth.uid() OR contact_user_id = auth.uid());
CREATE POLICY "contacts_insert" ON public.contacts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "contacts_update" ON public.contacts FOR UPDATE USING (user_id = auth.uid() OR contact_user_id = auth.uid());

-- ==================================================
-- 4. FUNKCJE APLIKACJI (UJEDNOLICONE)
-- ==================================================

-- FUNKCJA WYSZUKIWANIA UŻYTKOWNIKÓW (JEDNA WERSJA)
CREATE OR REPLACE FUNCTION public.get_searchable_users(
    search_query text DEFAULT '',
    result_limit integer DEFAULT 20
)
RETURNS TABLE(
    id uuid, 
    email text, 
    username text, 
    full_name text, 
    avatar_url text, 
    bio text, 
    phone text, 
    is_online boolean, 
    last_seen timestamp with time zone, 
    created_at timestamp with time zone, 
    updated_at timestamp with time zone, 
    contact_status text,
    is_blocked boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
        COALESCE(c.status, 'none') as contact_status,
        COALESCE(c.is_blocked, false) as is_blocked
    FROM users u
    LEFT JOIN contacts c ON (
        (c.user_id = auth.uid() AND c.contact_user_id = u.id) OR
        (c.contact_user_id = auth.uid() AND c.user_id = u.id)
    )
    WHERE 
        u.id != auth.uid()
        AND u.is_active = true
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

-- FUNKCJA TWORZENIA CZATU PRYWATNEGO
CREATE OR REPLACE FUNCTION public.create_direct_chat_with_members(
    user1 uuid,
    user2 uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    chat_id uuid;
    existing_chat_id uuid;
BEGIN
    -- Sprawdź czy już istnieje czat między tymi użytkownikami
    SELECT c.id INTO existing_chat_id
    FROM chats c
    JOIN chat_participants cp1 ON c.id = cp1.chat_id
    JOIN chat_participants cp2 ON c.id = cp2.chat_id
    WHERE c.type = 'direct'
        AND cp1.user_id = user1
        AND cp2.user_id = user2
        AND cp1.user_id != cp2.user_id;
    
    IF existing_chat_id IS NOT NULL THEN
        RETURN existing_chat_id;
    END IF;
    
    -- Tworzymy nowy czat jako prywatny
    INSERT INTO chats (type, is_group, created_by)
    VALUES ('direct', false, auth.uid())
    RETURNING id INTO chat_id;

    -- Dodajemy dwóch uczestników
    INSERT INTO chat_participants (chat_id, user_id, role)
    VALUES
        (chat_id, user1, 'member'),
        (chat_id, user2, 'member');

    RETURN chat_id;
END;
$$;

-- FUNKCJA TWORZENIA CZATU GRUPOWEGO
CREATE OR REPLACE FUNCTION public.create_group_chat(
    chat_name text,
    chat_description text DEFAULT NULL,
    member_ids uuid[] DEFAULT ARRAY[]::uuid[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    chat_id uuid;
    member_id uuid;
BEGIN
    -- Tworzymy nowy czat grupowy
    INSERT INTO chats (name, description, type, is_group, created_by)
    VALUES (chat_name, chat_description, 'group', true, auth.uid())
    RETURNING id INTO chat_id;

    -- Dodajemy twórcy jako właściciela
    INSERT INTO chat_participants (chat_id, user_id, role)
    VALUES (chat_id, auth.uid(), 'owner');

    -- Dodajemy pozostałych członków
    FOREACH member_id IN ARRAY member_ids
    LOOP
        INSERT INTO chat_participants (chat_id, user_id, role)
        VALUES (chat_id, member_id, 'member')
        ON CONFLICT (chat_id, user_id) DO NOTHING;
    END LOOP;

    RETURN chat_id;
END;
$$;

-- FUNKCJA DODAWANIA REAKCJI
CREATE OR REPLACE FUNCTION public.add_message_reaction(
    message_id uuid,
    reaction_emoji text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO message_reactions (message_id, user_id, emoji)
    VALUES (message_id, auth.uid(), reaction_emoji)
    ON CONFLICT (message_id, user_id, emoji) 
    DO UPDATE SET updated_at = NOW();

    RETURN true;
END;
$$;

-- FUNKCJA USUWANIA REAKCJI
CREATE OR REPLACE FUNCTION public.remove_message_reaction(
    message_id uuid,
    reaction_emoji text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM message_reactions
    WHERE message_id = remove_message_reaction.message_id
        AND user_id = auth.uid()
        AND emoji = reaction_emoji;

    RETURN FOUND;
END;
$$;

-- FUNKCJA ZARZĄDZANIA STATUSEM PISANIA
CREATE OR REPLACE FUNCTION public.set_typing_status(
    chat_id uuid,
    is_typing boolean
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF is_typing THEN
        INSERT INTO typing_indicators (chat_id, user_id, started_at)
        VALUES (chat_id, auth.uid(), NOW())
        ON CONFLICT (chat_id, user_id)
        DO UPDATE SET started_at = NOW();
    ELSE
        DELETE FROM typing_indicators
        WHERE chat_id = set_typing_status.chat_id AND user_id = auth.uid();
    END IF;

    RETURN true;
END;
$$;

-- FUNKCJA POBIERANIA STATYSTYK DLA ADMINÓW
CREATE OR REPLACE FUNCTION public.get_app_statistics()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    stats jsonb;
    admin_role TEXT;
BEGIN
    -- Sprawdź uprawnienia
    SELECT role INTO admin_role FROM admin_roles WHERE user_id = auth.uid();
    
    IF admin_role IS NULL THEN
        RAISE EXCEPTION 'Access denied: Admin role required';
    END IF;

    SELECT jsonb_build_object(
        'total_users', (SELECT COUNT(*) FROM users),
        'active_users', (SELECT COUNT(*) FROM users WHERE is_active = true),
        'online_users', (SELECT COUNT(*) FROM users WHERE is_online = true),
        'total_chats', (SELECT COUNT(*) FROM chats),
        'total_messages', (SELECT COUNT(*) FROM messages WHERE is_deleted = false),
        'pending_reports', (SELECT COUNT(*) FROM reports WHERE status = 'pending'),
        'messages_today', (
            SELECT COUNT(*) FROM messages 
            WHERE created_at >= CURRENT_DATE AND is_deleted = false
        ),
        'new_users_today', (
            SELECT COUNT(*) FROM users 
            WHERE created_at >= CURRENT_DATE
        )
    ) INTO stats;

    RETURN stats;
END;
$$;

-- ==================================================
-- 5. UPRAWNIENIA
-- ==================================================

-- Nadaj uprawnienia do funkcji
GRANT EXECUTE ON FUNCTION public.get_searchable_users TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_group_chat TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_message_reaction TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_message_reaction TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_typing_status TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_statistics TO authenticated;

-- Nadaj uprawnienia do tabel
GRANT ALL ON public.users TO authenticated;
GRANT ALL ON public.chats TO authenticated;
GRANT ALL ON public.chat_participants TO authenticated;
GRANT ALL ON public.messages TO authenticated;
GRANT ALL ON public.contacts TO authenticated;
GRANT ALL ON public.message_reactions TO authenticated;
GRANT ALL ON public.typing_indicators TO authenticated;
GRANT ALL ON public.reports TO authenticated;
GRANT ALL ON public.admin_roles TO authenticated;
GRANT ALL ON public.admin_actions TO authenticated;

-- ==================================================
-- 6. TRIGGER DLA AUTOMATYCZNYCH AKTUALIZACJI
-- ==================================================

-- Funkcja do aktualizacji updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Triggery dla automatycznej aktualizacji updated_at
DROP TRIGGER IF EXISTS update_users_updated_at ON public.users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_chats_updated_at ON public.chats;
CREATE TRIGGER update_chats_updated_at
    BEFORE UPDATE ON public.chats
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_messages_updated_at ON public.messages;
CREATE TRIGGER update_messages_updated_at
    BEFORE UPDATE ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- ==================================================
-- KONIEC SKRYPTU
-- ==================================================

SELECT 'Database setup completed successfully!' as status;
