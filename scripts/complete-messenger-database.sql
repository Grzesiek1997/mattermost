-- KOMPLETNA BAZA DANYCH DLA KOMUNIKATORA TELEGRAM
-- Uruchom ten skrypt w Supabase SQL Editor

-- Wyłącz RLS tymczasowo
ALTER TABLE IF EXISTS public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.chats DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.chat_participants DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.contacts DISABLE ROW LEVEL SECURITY;

-- Usuń wszystkie istniejące tabele i funkcje
DROP TABLE IF EXISTS public.message_reactions CASCADE;
DROP TABLE IF EXISTS public.notifications CASCADE;
DROP TABLE IF EXISTS public.typing_indicators CASCADE;
DROP TABLE IF EXISTS public.message_reads CASCADE;
DROP TABLE IF EXISTS public.admin_actions CASCADE;
DROP TABLE IF EXISTS public.system_settings CASCADE;
DROP TABLE IF EXISTS public.user_reports CASCADE;
DROP TABLE IF EXISTS public.admin_users CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.chat_participants CASCADE;
DROP TABLE IF EXISTS public.chats CASCADE;
DROP TABLE IF EXISTS public.contacts CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;

-- Usuń wszystkie funkcje
DROP FUNCTION IF EXISTS public.get_searchable_users CASCADE;
DROP FUNCTION IF EXISTS public.create_direct_chat_with_members CASCADE;
DROP FUNCTION IF EXISTS public.is_admin CASCADE;
DROP FUNCTION IF EXISTS public.get_admin_role CASCADE;
DROP FUNCTION IF EXISTS public.create_first_super_admin CASCADE;
DROP FUNCTION IF EXISTS public.promote_user_to_admin CASCADE;
DROP FUNCTION IF EXISTS public.create_user_profile CASCADE;

-- 1. TABELA USERS
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

-- 2. TABELA CONTACTS
CREATE TABLE public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'blocked')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, contact_user_id)
);

-- 3. TABELA CHATS
CREATE TABLE public.chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    type TEXT DEFAULT 'direct' CHECK (type IN ('direct', 'group')),
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. TABELA CHAT_PARTICIPANTS
CREATE TABLE public.chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member' CHECK (role IN ('member', 'admin', 'owner')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- 5. TABELA MESSAGES
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'file', 'voice')),
    reply_to UUID REFERENCES public.messages(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. TABELA NOTIFICATIONS
CREATE TABLE public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('contact_invitation', 'message', 'system')),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    data JSONB DEFAULT '{}',
    read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 7. TABELA ADMIN_USERS
CREATE TABLE public.admin_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
    role TEXT DEFAULT 'admin' CHECK (role IN ('admin', 'super_admin')),
    permissions JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES public.users(id)
);

-- INDEKSY DLA WYDAJNOŚCI
CREATE INDEX idx_users_email ON public.users(email);
CREATE INDEX idx_users_username ON public.users(username);
CREATE INDEX idx_contacts_user_id ON public.contacts(user_id);
CREATE INDEX idx_contacts_status ON public.contacts(status);
CREATE INDEX idx_chat_participants_chat_id ON public.chat_participants(chat_id);
CREATE INDEX idx_chat_participants_user_id ON public.chat_participants(user_id);
CREATE INDEX idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX idx_messages_created_at ON public.messages(created_at);
CREATE INDEX idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX idx_notifications_read ON public.notifications(read);

-- WŁĄCZ RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- PROSTE POLITYKI RLS (BEZ REKURENCJI)
-- Users - wszyscy mogą czytać profile
CREATE POLICY "Users can view all profiles" ON public.users FOR SELECT USING (true);
CREATE POLICY "Users can insert their own profile" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON public.users FOR UPDATE USING (auth.uid() = id);

-- Contacts - użytkownicy widzą swoje kontakty
CREATE POLICY "Users can view their contacts" ON public.contacts FOR SELECT USING (auth.uid() = user_id OR auth.uid() = contact_user_id);
CREATE POLICY "Users can manage their contacts" ON public.contacts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their contacts" ON public.contacts FOR UPDATE USING (auth.uid() = user_id OR auth.uid() = contact_user_id);

-- Chats - użytkownicy widzą czaty w których uczestniczą
CREATE POLICY "Users can view their chats" ON public.chats FOR SELECT USING (
    id IN (SELECT chat_id FROM public.chat_participants WHERE user_id = auth.uid())
);
CREATE POLICY "Users can create chats" ON public.chats FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Chat participants - proste polityki
CREATE POLICY "Users can view chat participants" ON public.chat_participants FOR SELECT USING (
    user_id = auth.uid() OR chat_id IN (SELECT chat_id FROM public.chat_participants WHERE user_id = auth.uid())
);
CREATE POLICY "Users can join chats" ON public.chat_participants FOR INSERT WITH CHECK (true);

-- Messages - użytkownicy widzą wiadomości w swoich czatach
CREATE POLICY "Users can view messages in their chats" ON public.messages FOR SELECT USING (
    chat_id IN (SELECT chat_id FROM public.chat_participants WHERE user_id = auth.uid())
);
CREATE POLICY "Users can send messages" ON public.messages FOR INSERT WITH CHECK (
    auth.uid() = user_id AND chat_id IN (SELECT chat_id FROM public.chat_participants WHERE user_id = auth.uid())
);

-- Notifications - użytkownicy widzą swoje powiadomienia
CREATE POLICY "Users can view their notifications" ON public.notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update their notifications" ON public.notifications FOR UPDATE USING (auth.uid() = user_id);

-- Admin users - tylko admini widzą
CREATE POLICY "Admins can view admin users" ON public.admin_users FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid())
);

-- FUNKCJE SECURITY DEFINER (OMIJAJĄ RLS)
CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term TEXT DEFAULT '')
RETURNS TABLE(
    id UUID,
    username TEXT,
    full_name TEXT,
    email TEXT,
    avatar_url TEXT
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
        u.email,
        u.avatar_url
    FROM public.users u
    WHERE 
        (search_term = '' OR 
         u.username ILIKE '%' || search_term || '%' OR 
         u.full_name ILIKE '%' || search_term || '%' OR
         u.email ILIKE '%' || search_term || '%')
        AND u.id != COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::UUID)
    ORDER BY u.username
    LIMIT 50;
END;
$$;

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
    FROM public.chats c
    WHERE c.type = 'direct'
    AND EXISTS (SELECT 1 FROM public.chat_participants cp1 WHERE cp1.chat_id = c.id AND cp1.user_id = user1)
    AND EXISTS (SELECT 1 FROM public.chat_participants cp2 WHERE cp2.chat_id = c.id AND cp2.user_id = user2)
    LIMIT 1;
    
    IF existing_chat_id IS NOT NULL THEN
        RETURN existing_chat_id;
    END IF;
    
    -- Utwórz nowy czat
    INSERT INTO public.chats (type, created_by)
    VALUES ('direct', user1)
    RETURNING id INTO chat_id;
    
    -- Dodaj uczestników
    INSERT INTO public.chat_participants (chat_id, user_id, role)
    VALUES 
        (chat_id, user1, 'member'),
        (chat_id, user2, 'member');
    
    RETURN chat_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_users 
        WHERE user_id = COALESCE(user_uuid, auth.uid())
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

-- NADAJ UPRAWNIENIA
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon;

-- UTWÓRZ TESTOWYCH UŻYTKOWNIKÓW
INSERT INTO public.users (id, email, username, full_name) VALUES
('11111111-1111-1111-1111-111111111111', 'john@test.com', 'john', 'John Doe'),
('22222222-2222-2222-2222-222222222222', 'jane@test.com', 'jane', 'Jane Smith'),
('33333333-3333-3333-3333-333333333333', 'test@test.com', 'test', 'Test User')
ON CONFLICT (id) DO NOTHING;

-- WYNIK
SELECT 'Kompletna baza danych komunikatora została utworzona!' as status;
