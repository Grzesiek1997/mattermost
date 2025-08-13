-- KOMPLETNA BAZA DANYCH OD PODSTAW
-- Uruchom ten skrypt DOPIERO po wyczyszczeniu poprzednim skryptem

-- KROK 1: Utwórz tabele w odpowiedniej kolejności

-- Tabela users
CREATE TABLE public.users (
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

-- Tabela chats
CREATE TABLE public.chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    type TEXT DEFAULT 'direct' CHECK (type IN ('direct', 'group')),
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela chat_participants
CREATE TABLE public.chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member' CHECK (role IN ('member', 'admin', 'owner')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- Tabela messages
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'file', 'voice')),
    reply_to UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela contacts
CREATE TABLE public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'blocked')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, contact_user_id)
);

-- KROK 2: Utwórz indeksy dla wydajności
CREATE INDEX idx_users_email ON public.users(email);
CREATE INDEX idx_users_username ON public.users(username);
CREATE INDEX idx_chats_created_by ON public.chats(created_by);
CREATE INDEX idx_chat_participants_chat_id ON public.chat_participants(chat_id);
CREATE INDEX idx_chat_participants_user_id ON public.chat_participants(user_id);
CREATE INDEX idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX idx_messages_user_id ON public.messages(user_id);
CREATE INDEX idx_messages_created_at ON public.messages(created_at);
CREATE INDEX idx_contacts_user_id ON public.contacts(user_id);
CREATE INDEX idx_contacts_contact_user_id ON public.contacts(contact_user_id);

-- KROK 3: Utwórz PROSTE funkcje SECURITY DEFINER (omijają RLS)
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
    -- Sprawdź czy czat już istnieje
    SELECT c.id INTO existing_chat_id
    FROM chats c
    JOIN chat_participants cp1 ON c.id = cp1.chat_id
    JOIN chat_participants cp2 ON c.id = cp2.chat_id
    WHERE c.type = 'direct'
        AND cp1.user_id = user1
        AND cp2.user_id = user2;
    
    IF existing_chat_id IS NOT NULL THEN
        RETURN existing_chat_id;
    END IF;
    
    -- Utwórz nowy czat
    INSERT INTO chats (type, created_by)
    VALUES ('direct', user1)
    RETURNING id INTO chat_id;
    
    -- Dodaj uczestników
    INSERT INTO chat_participants (chat_id, user_id, role)
    VALUES 
        (chat_id, user1, 'member'),
        (chat_id, user2, 'member');
    
    RETURN chat_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term TEXT)
RETURNS TABLE(id UUID, username TEXT, full_name TEXT, email TEXT, avatar_url TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, u.username, u.full_name, u.email, u.avatar_url
    FROM users u
    WHERE u.id != auth.uid()
        AND (
            u.username ILIKE '%' || search_term || '%' OR
            u.full_name ILIKE '%' || search_term || '%' OR
            u.email ILIKE '%' || search_term || '%'
        )
    LIMIT 20;
END;
$$;

-- KROK 4: Utwórz BARDZO PROSTE polityki RLS (bez rekurencji)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

-- Polityki dla users (bardzo proste)
CREATE POLICY "Anyone can view user profiles" ON public.users FOR SELECT USING (true);
CREATE POLICY "Users can insert their own profile" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON public.users FOR UPDATE USING (auth.uid() = id);

-- Polityki dla chats (bardzo proste)
CREATE POLICY "Users can view chats" ON public.chats FOR SELECT USING (true);
CREATE POLICY "Users can create chats" ON public.chats FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Polityki dla chat_participants (bardzo proste - BEZ REKURENCJI)
CREATE POLICY "Users can view participants" ON public.chat_participants FOR SELECT USING (true);
CREATE POLICY "Users can join chats" ON public.chat_participants FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Polityki dla messages (bardzo proste)
CREATE POLICY "Users can view messages" ON public.messages FOR SELECT USING (true);
CREATE POLICY "Users can send messages" ON public.messages FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Polityki dla contacts (bardzo proste)
CREATE POLICY "Users can view contacts" ON public.contacts FOR SELECT USING (auth.uid() = user_id OR auth.uid() = contact_user_id);
CREATE POLICY "Users can manage contacts" ON public.contacts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update contacts" ON public.contacts FOR UPDATE USING (auth.uid() = user_id OR auth.uid() = contact_user_id);

-- KROK 5: Nadaj uprawnienia
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon;

-- KROK 6: Test końcowy
SELECT 'Baza danych utworzona pomyślnie!' as status;
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;
