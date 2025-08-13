-- =====================================================
-- TELEGRAM CLONE - CZYSTA BAZA DANYCH OD PODSTAW
-- =====================================================

-- Wyłącz RLS tymczasowo
ALTER DEFAULT PRIVILEGES REVOKE ALL ON TABLES FROM anon, authenticated;

-- =====================================================
-- 1. TABELE PODSTAWOWE
-- =====================================================

-- Tabela użytkowników
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT auth.uid(),
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE NOT NULL,
    full_name TEXT DEFAULT 'User',
    bio TEXT,
    avatar_url TEXT,
    phone TEXT,
    is_online BOOLEAN DEFAULT false,
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela czatów
CREATE TABLE IF NOT EXISTS public.chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    type TEXT NOT NULL DEFAULT 'direct', -- 'direct' lub 'group'
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela uczestników czatów
CREATE TABLE IF NOT EXISTS public.chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member', -- 'member', 'admin', 'owner'
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- Tabela wiadomości
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text',
    reply_to UUID REFERENCES public.messages(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela kontaktów
CREATE TABLE IF NOT EXISTS public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending', -- 'pending', 'accepted', 'blocked'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, contact_user_id)
);

-- Tabela powiadomień
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL, -- 'contact_request', 'message', 'system'
    title TEXT NOT NULL,
    message TEXT,
    data JSONB,
    read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =====================================================
-- 2. INDEKSY DLA WYDAJNOŚCI
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON public.users(username);
CREATE INDEX IF NOT EXISTS idx_chat_participants_chat_id ON public.chat_participants(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON public.chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at);
CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON public.contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON public.contacts(status);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);

-- =====================================================
-- 3. FUNKCJE BEZPIECZNE (SECURITY DEFINER)
-- =====================================================

-- Funkcja do tworzenia czatu bezpośredniego
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
    existing_chat_id UUID;
    new_chat_id UUID;
BEGIN
    -- Sprawdź czy czat już istnieje
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
    );
    
    -- Jeśli czat istnieje, zwróć jego ID
    IF existing_chat_id IS NOT NULL THEN
        RETURN existing_chat_id;
    END IF;
    
    -- Utwórz nowy czat
    INSERT INTO chats (type, created_by)
    VALUES ('direct', user1)
    RETURNING id INTO new_chat_id;
    
    -- Dodaj uczestników
    INSERT INTO chat_participants (chat_id, user_id, role)
    VALUES 
        (new_chat_id, user1, 'member'),
        (new_chat_id, user2, 'member');
    
    RETURN new_chat_id;
END;
$$;

-- Funkcja do wyszukiwania użytkowników
CREATE OR REPLACE FUNCTION public.get_searchable_users(
    search_term TEXT DEFAULT '',
    current_user_id UUID DEFAULT auth.uid()
)
RETURNS TABLE(
    id UUID,
    username TEXT,
    full_name TEXT,
    avatar_url TEXT,
    email TEXT
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
        u.email
    FROM users u
    WHERE u.id != current_user_id
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

-- Funkcja do tworzenia profilu użytkownika
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
    -- Sprawdź czy user już istnieje
    SELECT * INTO new_user FROM public.users WHERE id = user_id;
    
    IF new_user.id IS NOT NULL THEN
        RETURN new_user;
    END IF;
    
    -- Utwórz nowy profil
    INSERT INTO public.users (
        id,
        email,
        username,
        full_name,
        is_online,
        last_seen
    ) VALUES (
        user_id,
        user_email,
        user_username,
        user_full_name,
        true,
        NOW()
    ) RETURNING * INTO new_user;
    
    RETURN new_user;
END;
$$;

-- =====================================================
-- 4. PROSTE POLITYKI RLS (BEZ REKURENCJI)
-- =====================================================

-- Włącz RLS dla wszystkich tabel
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Polityki dla users (wszyscy mogą widzieć profile)
CREATE POLICY "Anyone can view user profiles" ON public.users
    FOR SELECT USING (true);

CREATE POLICY "Users can insert their own profile" ON public.users
    FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON public.users
    FOR UPDATE USING (auth.uid() = id);

-- Polityki dla chats (tylko uczestnicy)
CREATE POLICY "Users can view their chats" ON public.chats
    FOR SELECT USING (
        auth.uid() IN (
            SELECT user_id FROM chat_participants WHERE chat_id = chats.id
        )
    );

CREATE POLICY "Users can create chats" ON public.chats
    FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Polityki dla chat_participants (tylko uczestnicy)
CREATE POLICY "Users can view chat participants" ON public.chat_participants
    FOR SELECT USING (
        auth.uid() = user_id OR 
        auth.uid() IN (
            SELECT cp.user_id FROM chat_participants cp WHERE cp.chat_id = chat_participants.chat_id
        )
    );

CREATE POLICY "Users can join chats" ON public.chat_participants
    FOR INSERT WITH CHECK (true);

-- Polityki dla messages (tylko uczestnicy czatu)
CREATE POLICY "Users can view messages in their chats" ON public.messages
    FOR SELECT USING (
        auth.uid() IN (
            SELECT user_id FROM chat_participants WHERE chat_id = messages.chat_id
        )
    );

CREATE POLICY "Users can send messages" ON public.messages
    FOR INSERT WITH CHECK (
        auth.uid() = user_id AND
        auth.uid() IN (
            SELECT user_id FROM chat_participants WHERE chat_id = messages.chat_id
        )
    );

-- Polityki dla contacts
CREATE POLICY "Users can view their contacts" ON public.contacts
    FOR SELECT USING (auth.uid() = user_id OR auth.uid() = contact_user_id);

CREATE POLICY "Users can manage their contacts" ON public.contacts
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their contacts" ON public.contacts
    FOR UPDATE USING (auth.uid() = user_id OR auth.uid() = contact_user_id);

-- Polityki dla notifications
CREATE POLICY "Users can view their notifications" ON public.notifications
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update their notifications" ON public.notifications
    FOR UPDATE USING (auth.uid() = user_id);

-- =====================================================
-- 5. UPRAWNIENIA
-- =====================================================

-- Nadaj uprawnienia dla authenticated users
GRANT ALL ON public.users TO authenticated;
GRANT ALL ON public.chats TO authenticated;
GRANT ALL ON public.chat_participants TO authenticated;
GRANT ALL ON public.messages TO authenticated;
GRANT ALL ON public.contacts TO authenticated;
GRANT ALL ON public.notifications TO authenticated;

-- Nadaj uprawnienia do funkcji
GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_searchable_users TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_user_profile TO authenticated;

-- =====================================================
-- 6. TRIGGERY DLA AUTOMATYCZNYCH AKCJI
-- =====================================================

-- Trigger do aktualizacji updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Dodaj triggery do tabel
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_chats_updated_at BEFORE UPDATE ON public.chats
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_messages_updated_at BEFORE UPDATE ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- =====================================================
-- GOTOWE! 🎉
-- =====================================================

SELECT 'Baza danych została utworzona pomyślnie! ✅' as status;
