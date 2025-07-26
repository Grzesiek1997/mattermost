-- KOMPLETNA KONFIGURACJA BAZY DANYCH TELEGRAM CLONE
-- Uruchom to w SQL Editor w Supabase (po kolei, każdy blok osobno)

-- ============================================
-- BLOK 1: TWORZENIE TABEL
-- ============================================

-- Usuń istniejące tabele jeśli istnieją (ostrożnie!)
DROP TABLE IF EXISTS public.message_reactions CASCADE;
DROP TABLE IF EXISTS public.typing_indicators CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.chat_members CASCADE;
DROP TABLE IF EXISTS public.chat_participants CASCADE;
DROP TABLE IF EXISTS public.contacts CASCADE;
DROP TABLE IF EXISTS public.chats CASCADE;
DROP TABLE IF EXISTS public.admin_roles CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;

-- Tabela użytkowników
CREATE TABLE public.users (
    id UUID PRIMARY KEY DEFAULT auth.uid(),
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

-- Tabela ról administratorów
CREATE TABLE public.admin_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'super_admin', 'moderator')),
    granted_by UUID REFERENCES public.users(id),
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Tabela czatów
CREATE TABLE public.chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type TEXT NOT NULL DEFAULT 'direct' CHECK (type IN ('direct', 'group', 'channel')),
    title TEXT,
    description TEXT,
    avatar_url TEXT,
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_message_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela uczestników czatów
CREATE TABLE public.chat_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    can_send_messages BOOLEAN DEFAULT true,
    can_add_members BOOLEAN DEFAULT false,
    can_delete_messages BOOLEAN DEFAULT false,
    UNIQUE(chat_id, user_id)
);

-- Tabela wiadomości
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT,
    message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'file', 'voice', 'video')),
    file_url TEXT,
    file_name TEXT,
    file_size INTEGER,
    reply_to_id UUID REFERENCES public.messages(id),
    thread_id UUID REFERENCES public.messages(id),
    is_edited BOOLEAN DEFAULT false,
    is_deleted BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela reakcji na wiadomości
CREATE TABLE public.message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id, emoji)
);

-- Tabela kontaktów
CREATE TABLE public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'blocked')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, contact_user_id)
);

-- Tabela wskaźników pisania
CREATE TABLE public.typing_indicators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    is_typing BOOLEAN DEFAULT false,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- ============================================
-- BLOK 2: INDEKSY DLA WYDAJNOŚCI
-- ============================================

-- Indeksy dla users
CREATE INDEX idx_users_email ON public.users(email);
CREATE INDEX idx_users_username ON public.users(username);
CREATE INDEX idx_users_is_online ON public.users(is_online);

-- Indeksy dla messages
CREATE INDEX idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX idx_messages_user_id ON public.messages(user_id);
CREATE INDEX idx_messages_created_at ON public.messages(created_at DESC);
CREATE INDEX idx_messages_reply_to_id ON public.messages(reply_to_id);

-- Indeksy dla chat_members
CREATE INDEX idx_chat_members_chat_id ON public.chat_members(chat_id);
CREATE INDEX idx_chat_members_user_id ON public.chat_members(user_id);

-- Indeksy dla contacts
CREATE INDEX idx_contacts_user_id ON public.contacts(user_id);
CREATE INDEX idx_contacts_contact_user_id ON public.contacts(contact_user_id);
CREATE INDEX idx_contacts_status ON public.contacts(status);

-- ============================================
-- BLOK 3: WŁĄCZENIE RLS (ROW LEVEL SECURITY)
-- ============================================

-- Włącz RLS dla wszystkich tabel
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;

-- ============================================
-- BLOK 4: POLITYKI RLS
-- ============================================

-- Polityki dla users
DROP POLICY IF EXISTS "Users can view all profiles" ON public.users;
CREATE POLICY "Users can view all profiles" ON public.users 
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.users;
CREATE POLICY "Users can insert their own profile" ON public.users 
    FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
CREATE POLICY "Users can update their own profile" ON public.users 
    FOR UPDATE USING (auth.uid() = id);

-- Polityki dla admin_roles
DROP POLICY IF EXISTS "Admins can view admin roles" ON public.admin_roles;
CREATE POLICY "Admins can view admin roles" ON public.admin_roles 
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.admin_roles WHERE user_id = auth.uid())
    );

DROP POLICY IF EXISTS "Super admins can manage admin roles" ON public.admin_roles;
CREATE POLICY "Super admins can manage admin roles" ON public.admin_roles 
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.admin_roles 
            WHERE user_id = auth.uid() AND role = 'super_admin'
        )
    );

-- Polityki dla chats
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
CREATE POLICY "Users can view their chats" ON public.chats 
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.chat_members 
            WHERE chat_id = chats.id AND user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can create chats" ON public.chats;
CREATE POLICY "Users can create chats" ON public.chats 
    FOR INSERT WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS "Chat owners can update chats" ON public.chats;
CREATE POLICY "Chat owners can update chats" ON public.chats 
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.chat_members 
            WHERE chat_id = chats.id AND user_id = auth.uid() 
            AND role IN ('owner', 'admin')
        )
    );

-- Polityki dla chat_members
DROP POLICY IF EXISTS "Users can view chat members" ON public.chat_members;
CREATE POLICY "Users can view chat members" ON public.chat_members 
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.chat_members cm 
            WHERE cm.chat_id = chat_members.chat_id AND cm.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can join chats" ON public.chat_members;
CREATE POLICY "Users can join chats" ON public.chat_members 
    FOR INSERT WITH CHECK (true);

-- Polityki dla messages
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
CREATE POLICY "Users can view messages in their chats" ON public.messages 
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.chat_members 
            WHERE chat_id = messages.chat_id AND user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
CREATE POLICY "Users can send messages" ON public.messages 
    FOR INSERT WITH CHECK (
        auth.uid() = user_id AND
        EXISTS (
            SELECT 1 FROM public.chat_members 
            WHERE chat_id = messages.chat_id AND user_id = auth.uid()
            AND can_send_messages = true
        )
    );

DROP POLICY IF EXISTS "Users can update their own messages" ON public.messages;
CREATE POLICY "Users can update their own messages" ON public.messages 
    FOR UPDATE USING (auth.uid() = user_id);

-- Polityki dla message_reactions
DROP POLICY IF EXISTS "Users can view reactions" ON public.message_reactions;
CREATE POLICY "Users can view reactions" ON public.message_reactions 
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.messages m
            JOIN public.chat_members cm ON m.chat_id = cm.chat_id
            WHERE m.id = message_reactions.message_id AND cm.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can manage their reactions" ON public.message_reactions;
CREATE POLICY "Users can manage their reactions" ON public.message_reactions 
    FOR ALL USING (auth.uid() = user_id);

-- Polityki dla contacts
DROP POLICY IF EXISTS "Users can view their contacts" ON public.contacts;
CREATE POLICY "Users can view their contacts" ON public.contacts 
    FOR SELECT USING (
        auth.uid() = user_id OR auth.uid() = contact_user_id
    );

DROP POLICY IF EXISTS "Users can manage their contacts" ON public.contacts;
CREATE POLICY "Users can manage their contacts" ON public.contacts 
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their contacts" ON public.contacts;
CREATE POLICY "Users can update their contacts" ON public.contacts 
    FOR UPDATE USING (
        auth.uid() = user_id OR auth.uid() = contact_user_id
    );

-- Polityki dla typing_indicators
DROP POLICY IF EXISTS "Users can view typing indicators" ON public.typing_indicators;
CREATE POLICY "Users can view typing indicators" ON public.typing_indicators 
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.chat_members 
            WHERE chat_id = typing_indicators.chat_id AND user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can manage their typing status" ON public.typing_indicators;
CREATE POLICY "Users can manage their typing status" ON public.typing_indicators 
    FOR ALL USING (auth.uid() = user_id);
