-- Poprawiony schemat bazy danych dla komunikatora mobilnego
-- Supabase + PostgreSQL

-- Włącz rozszerzenia
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ====================================
-- 1. TABELA UŻYTKOWNIKÓW
-- ====================================
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username VARCHAR(50) UNIQUE NOT NULL,
    full_name VARCHAR(100),
    avatar_url TEXT,
    bio TEXT,
    is_online BOOLEAN DEFAULT false,
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ====================================
-- 2. TABELA ZAPROSZEŃ DO ZNAJOMYCH
-- ====================================
CREATE TABLE public.friend_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    responded_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(sender_id, receiver_id)
);

-- ====================================
-- 3. TABELA ZNAJOMYCH
-- ====================================
CREATE TABLE public.friendships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user1_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    user2_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user1_id, user2_id),
    CHECK (user1_id < user2_id) -- Zapobiega duplikatom (A->B i B->A)
);

-- ====================================
-- 4. TABELA KONWERSACJI
-- ====================================
CREATE TABLE public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type VARCHAR(20) NOT NULL DEFAULT 'direct' CHECK (type IN ('direct', 'group')),
    name VARCHAR(100), -- Tylko dla grup
    avatar_url TEXT, -- Tylko dla grup
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_message_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ====================================
-- 5. TABELA UCZESTNIKÓW KONWERSACJI
-- ====================================
CREATE TABLE public.conversation_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    UNIQUE(conversation_id, user_id)
);

-- ====================================
-- 6. TABELA WIADOMOŚCI
-- ====================================
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'file', 'system')),
    reply_to_id UUID REFERENCES public.messages(id),
    is_edited BOOLEAN DEFAULT false,
    is_deleted BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ====================================
-- 7. TABELA ODCZYTANYCH WIADOMOŚCI
-- ====================================
CREATE TABLE public.message_reads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id)
);

-- ====================================
-- INDEKSY DLA WYDAJNOŚCI
-- ====================================
CREATE INDEX idx_profiles_username ON public.profiles(username);
CREATE INDEX idx_friend_requests_receiver ON public.friend_requests(receiver_id);
CREATE INDEX idx_friend_requests_sender ON public.friend_requests(sender_id);
CREATE INDEX idx_friend_requests_status ON public.friend_requests(status);
CREATE INDEX idx_friendships_user1 ON public.friendships(user1_id);
CREATE INDEX idx_friendships_user2 ON public.friendships(user2_id);
CREATE INDEX idx_conversations_type ON public.conversations(type);
CREATE INDEX idx_conversation_participants_conversation ON public.conversation_participants(conversation_id);
CREATE INDEX idx_conversation_participants_user ON public.conversation_participants(user_id);
CREATE INDEX idx_messages_conversation ON public.messages(conversation_id);
CREATE INDEX idx_messages_sender ON public.messages(sender_id);
CREATE INDEX idx_messages_created_at ON public.messages(created_at);
CREATE INDEX idx_message_reads_message ON public.message_reads(message_id);
CREATE INDEX idx_message_reads_user ON public.message_reads(user_id);

-- ====================================
-- WŁĄCZENIE ROW LEVEL SECURITY
-- ====================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;

-- ====================================
-- POLITYKI RLS
-- ====================================

-- Profile - każdy może przeglądać, tylko swój profil może edytować
CREATE POLICY "Wszyscy mogą przeglądać profile" ON public.profiles
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Użytkownicy mogą tworzyć swój profil" ON public.profiles
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

CREATE POLICY "Użytkownicy mogą edytować swój profil" ON public.profiles
    FOR UPDATE TO authenticated USING (auth.uid() = id);

-- Zaproszenia do znajomych
CREATE POLICY "Użytkownicy mogą przeglądać swoje zaproszenia" ON public.friend_requests
    FOR SELECT TO authenticated 
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

CREATE POLICY "Użytkownicy mogą wysyłać zaproszenia" ON public.friend_requests
    FOR INSERT TO authenticated 
    WITH CHECK (sender_id = auth.uid());

CREATE POLICY "Użytkownicy mogą odpowiadać na zaproszenia" ON public.friend_requests
    FOR UPDATE TO authenticated 
    USING (receiver_id = auth.uid());

-- Znajomości
CREATE POLICY "Użytkownicy mogą przeglądać swoje znajomości" ON public.friendships
    FOR SELECT TO authenticated 
    USING (user1_id = auth.uid() OR user2_id = auth.uid());

-- Konwersacje
CREATE POLICY "Użytkownicy mogą przeglądać swoje konwersacje" ON public.conversations
    FOR SELECT TO authenticated 
    USING (
        id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid() AND is_active = true
        )
    );

CREATE POLICY "Użytkownicy mogą tworzyć konwersacje" ON public.conversations
    FOR INSERT TO authenticated 
    WITH CHECK (created_by = auth.uid());

-- Uczestnicy konwersacji
CREATE POLICY "Użytkownicy mogą przeglądać uczestników swoich konwersacji" ON public.conversation_participants
    FOR SELECT TO authenticated 
    USING (
        conversation_id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid() AND is_active = true
        )
    );

CREATE POLICY "Użytkownicy mogą dołączać do konwersacji" ON public.conversation_participants
    FOR INSERT TO authenticated 
    WITH CHECK (user_id = auth.uid());

-- Wiadomości
CREATE POLICY "Użytkownicy mogą przeglądać wiadomości ze swoich konwersacji" ON public.messages
    FOR SELECT TO authenticated 
    USING (
        conversation_id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid() AND is_active = true
        )
    );

CREATE POLICY "Użytkownicy mogą wysyłać wiadomości" ON public.messages
    FOR INSERT TO authenticated 
    WITH CHECK (
        sender_id = auth.uid() AND
        conversation_id IN (
            SELECT conversation_id 
            FROM public.conversation_participants 
            WHERE user_id = auth.uid() AND is_active = true
        )
    );

CREATE POLICY "Użytkownicy mogą edytować swoje wiadomości" ON public.messages
    FOR UPDATE TO authenticated 
    USING (sender_id = auth.uid());

-- Odczytane wiadomości
CREATE POLICY "Użytkownicy mogą zarządzać statusem odczytania" ON public.message_reads
    FOR ALL TO authenticated 
    USING (user_id = auth.uid());

-- ====================================
-- FUNKCJE POMOCNICZE
-- ====================================

-- Funkcja wyszukiwania użytkowników
CREATE OR REPLACE FUNCTION search_users(search_term TEXT)
RETURNS TABLE(
    id UUID,
    username VARCHAR,
    full_name VARCHAR,
    avatar_url TEXT,
    is_online BOOLEAN
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
        p.is_online
    FROM public.profiles p
    WHERE 
        p.id != auth.uid() AND
        (p.username ILIKE '%' || search_term || '%' OR 
         p.full_name ILIKE '%' || search_term || '%')
    ORDER BY p.username
    LIMIT 50;
END;
$$;

-- Funkcja tworzenia konwersacji bezpośredniej
CREATE OR REPLACE FUNCTION create_direct_conversation(other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    conversation_id UUID;
    existing_conversation_id UUID;
    current_user_id UUID := auth.uid();
BEGIN
    -- Sprawdź czy konwersacja już istnieje
    SELECT c.id INTO existing_conversation_id
    FROM public.conversations c
    WHERE c.type = 'direct'
    AND EXISTS (
        SELECT 1 FROM public.conversation_participants cp1 
        WHERE cp1.conversation_id = c.id 
        AND cp1.user_id = current_user_id 
        AND cp1.is_active = true
    )
    AND EXISTS (
        SELECT 1 FROM public.conversation_participants cp2 
        WHERE cp2.conversation_id = c.id 
        AND cp2.user_id = other_user_id 
        AND cp2.is_active = true
    );
    
    IF existing_conversation_id IS NOT NULL THEN
        RETURN existing_conversation_id;
    END IF;
    
    -- Utwórz nową konwersację
    INSERT INTO public.conversations (type, created_by)
    VALUES ('direct', current_user_id)
    RETURNING id INTO conversation_id;
    
    -- Dodaj uczestników
    INSERT INTO public.conversation_participants (conversation_id, user_id)
    VALUES 
        (conversation_id, current_user_id),
        (conversation_id, other_user_id);
    
    RETURN conversation_id;
END;
$$;

-- Funkcja akceptowania zaproszenia do znajomych
CREATE OR REPLACE FUNCTION accept_friend_request(request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    sender_id UUID;
    receiver_id UUID;
    user1_id UUID;
    user2_id UUID;
BEGIN
    -- Pobierz dane zaproszenia
    SELECT fr.sender_id, fr.receiver_id INTO sender_id, receiver_id
    FROM public.friend_requests fr
    WHERE fr.id = request_id 
    AND fr.receiver_id = auth.uid() 
    AND fr.status = 'pending';
    
    IF sender_id IS NULL THEN
        RETURN false;
    END IF;
    
    -- Ustaw kolejność ID (mniejsze jako user1_id)
    IF sender_id < receiver_id THEN
        user1_id := sender_id;
        user2_id := receiver_id;
    ELSE
        user1_id := receiver_id;
        user2_id := sender_id;
    END IF;
    
    -- Zaktualizuj status zaproszenia
    UPDATE public.friend_requests 
    SET status = 'accepted', responded_at = NOW()
    WHERE id = request_id;
    
    -- Dodaj znajomość
    INSERT INTO public.friendships (user1_id, user2_id)
    VALUES (user1_id, user2_id)
    ON CONFLICT DO NOTHING;
    
    RETURN true;
END;
$$;

-- Funkcja sprawdzania czy użytkownicy są znajomymi
CREATE OR REPLACE FUNCTION are_friends(user1_id UUID, user2_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    min_id UUID;
    max_id UUID;
    friendship_exists BOOLEAN := false;
BEGIN
    -- Ustaw kolejność ID
    IF user1_id < user2_id THEN
        min_id := user1_id;
        max_id := user2_id;
    ELSE
        min_id := user2_id;
        max_id := user1_id;
    END IF;
    
    -- Sprawdź czy znajomość istnieje
    SELECT EXISTS(
        SELECT 1 FROM public.friendships 
        WHERE user1_id = min_id AND user2_id = max_id
    ) INTO friendship_exists;
    
    RETURN friendship_exists;
END;
$$;

-- Ustaw uprawnienia
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Komentarz o ukończeniu
SELECT 'Schemat bazy danych komunikatora został utworzony pomyślnie!' as status;
