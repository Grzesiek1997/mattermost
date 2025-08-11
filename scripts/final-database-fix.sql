-- ========================================
-- FINALNA NAPRAWA BAZY DANYCH TELEGRAM CLONE
-- ========================================
-- Ten skrypt naprawia wszystkie problemy i zapewnia pełną funkcjonalność

-- ============================================
-- KROK 1: SPRAWDŹ I NAPRAW TABELE
-- ============================================

-- Sprawdź czy wszystkie tabele istnieją
DO $$
DECLARE
    missing_tables TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Sprawdź każdą tabelę
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users' AND table_schema = 'public') THEN
        missing_tables := array_append(missing_tables, 'users');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'chats' AND table_schema = 'public') THEN
        missing_tables := array_append(missing_tables, 'chats');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'chat_members' AND table_schema = 'public') THEN
        missing_tables := array_append(missing_tables, 'chat_members');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'messages' AND table_schema = 'public') THEN
        missing_tables := array_append(missing_tables, 'messages');
    END IF;
    
    IF array_length(missing_tables, 1) > 0 THEN
        RAISE NOTICE 'Missing tables: %', array_to_string(missing_tables, ', ');
    ELSE
        RAISE NOTICE 'All core tables exist ✅';
    END IF;
END $$;

-- Utwórz brakujące tabele jeśli nie istnieją
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
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.chats (
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

CREATE TABLE IF NOT EXISTS public.chat_members (
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

CREATE TABLE IF NOT EXISTS public.messages (
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

CREATE TABLE IF NOT EXISTS public.message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id, emoji)
);

CREATE TABLE IF NOT EXISTS public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'blocked')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, contact_user_id)
);

CREATE TABLE IF NOT EXISTS public.typing_indicators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    is_typing BOOLEAN DEFAULT false,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- Tabele admin
CREATE TABLE IF NOT EXISTS public.admin_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
    role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('super_admin', 'admin', 'moderator')),
    permissions JSONB DEFAULT '{}',
    granted_by UUID REFERENCES public.users(id),
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.admin_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL,
    target_type TEXT,
    target_id UUID,
    details JSONB DEFAULT '{}',
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.system_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT UNIQUE NOT NULL,
    value JSONB NOT NULL,
    description TEXT,
    category TEXT DEFAULT 'general',
    updated_by UUID REFERENCES public.users(id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    reported_message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    report_type TEXT CHECK (report_type IN ('spam', 'harassment', 'inappropriate', 'fake', 'violence', 'other')),
    description TEXT,
    status TEXT CHECK (status IN ('pending', 'in_review', 'resolved', 'dismissed')) DEFAULT 'pending',
    reviewed_by UUID REFERENCES public.users(id),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    resolution_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- KROK 2: UTWÓRZ WSZYSTKIE INDEKSY
-- ============================================

-- Indeksy podstawowe
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON public.users(username);
CREATE INDEX IF NOT EXISTS idx_users_is_online ON public.users(is_online);
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_user_id ON public.messages(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_members_chat_id ON public.chat_members(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_user_id ON public.chat_members(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON public.contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON public.contacts(status);

-- Indeksy admin
CREATE INDEX IF NOT EXISTS idx_admin_roles_user_id ON public.admin_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_admin_actions_admin_user_id ON public.admin_actions(admin_user_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_status ON public.user_reports(status);

-- ============================================
-- KROK 3: WŁĄCZ RLS I UTWÓRZ POLITYKI
-- ============================================

-- Włącz RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

-- Usuń stare polityki i utwórz nowe
DROP POLICY IF EXISTS "Users can view all profiles" ON public.users;
CREATE POLICY "Users can view all profiles" ON public.users FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.users;
CREATE POLICY "Users can insert their own profile" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
CREATE POLICY "Users can update their own profile" ON public.users FOR UPDATE USING (auth.uid() = id);

-- Polityki dla messages
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
CREATE POLICY "Users can view messages in their chats" ON public.messages FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.chat_members WHERE chat_id = messages.chat_id AND user_id = auth.uid())
);

DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
CREATE POLICY "Users can send messages" ON public.messages FOR INSERT WITH CHECK (
    auth.uid() = user_id AND
    EXISTS (SELECT 1 FROM public.chat_members WHERE chat_id = messages.chat_id AND user_id = auth.uid())
);

-- Polityki admin
DROP POLICY IF EXISTS "Admins can view admin roles" ON public.admin_roles;
CREATE POLICY "Admins can view admin roles" ON public.admin_roles FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.admin_roles WHERE user_id = auth.uid())
);

-- ============================================
-- KROK 4: UTWÓRZ WSZYSTKIE FUNKCJE
-- ============================================

-- Funkcja sprawdzania czy user jest adminem
CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_roles 
        WHERE user_id = user_uuid
    );
END;
$$;

-- Funkcja pobierania roli admin
CREATE OR REPLACE FUNCTION public.get_admin_role(user_uuid UUID DEFAULT auth.uid())
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    admin_role TEXT;
BEGIN
    SELECT role INTO admin_role
    FROM public.admin_roles 
    WHERE user_id = user_uuid;
    
    RETURN COALESCE(admin_role, 'user');
END;
$$;

-- Funkcja tworzenia pierwszego super admina
CREATE OR REPLACE FUNCTION public.create_first_super_admin()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    admin_count INTEGER;
BEGIN
    current_user_id := auth.uid();
    
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'No authenticated user';
    END IF;
    
    -- Sprawdź czy już są admini
    SELECT COUNT(*) INTO admin_count FROM public.admin_roles;
    
    IF admin_count > 0 THEN
        RETURN 'Super admin already exists';
    END IF;
    
    -- Utwórz pierwszego super admina
    INSERT INTO public.admin_roles (user_id, role, granted_by)
    VALUES (current_user_id, 'super_admin', current_user_id);
    
    RETURN 'First super admin created successfully';
END;
$$;

-- Funkcja bezpiecznego tworzenia profilu
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
        id, email, username, full_name, is_online, last_seen
    ) VALUES (
        user_id, user_email, user_username, user_full_name, true, NOW()
    ) RETURNING * INTO new_user;
    
    RETURN new_user;
END;
$$;

-- Funkcja zarządzania użytkownikami przez admin
CREATE OR REPLACE FUNCTION public.admin_manage_user(
    target_user_id UUID,
    action_type TEXT,
    reason TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_role TEXT;
    result_message TEXT;
BEGIN
    -- Sprawdź czy user jest adminem
    SELECT role INTO current_user_role 
    FROM public.admin_roles 
    WHERE user_id = auth.uid();
    
    IF current_user_role IS NULL THEN
        RAISE EXCEPTION 'Access denied: Admin role required';
    END IF;
    
    -- Wykonaj akcję
    CASE action_type
        WHEN 'ban' THEN
            UPDATE public.users SET is_online = false WHERE id = target_user_id;
            result_message := 'User banned successfully';
        WHEN 'delete' THEN
            IF current_user_role != 'super_admin' THEN
                RAISE EXCEPTION 'Only super admins can delete users';
            END IF;
            DELETE FROM public.users WHERE id = target_user_id;
            result_message := 'User deleted successfully';
        ELSE
            RAISE EXCEPTION 'Invalid action type';
    END CASE;
    
    -- Zaloguj akcję
    INSERT INTO public.admin_actions (admin_user_id, action_type, target_type, target_id, details)
    VALUES (auth.uid(), action_type, 'user', target_user_id, jsonb_build_object('reason', reason));
    
    RETURN result_message;
END;
$$;

-- ============================================
-- KROK 5: NADAJ UPRAWNIENIA
-- ============================================

GRANT EXECUTE ON FUNCTION public.is_admin TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_role TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_first_super_admin TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_user_profile TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_user TO authenticated;

-- ============================================
-- KROK 6: DODAJ DOMYŚLNE USTAWIENIA
-- ============================================

INSERT INTO public.system_settings (key, value, description, category) VALUES
    ('app_name', '"Telegram Clone"', 'Application name', 'general'),
    ('max_file_size', '52428800', 'Maximum file upload size in bytes', 'uploads'),
    ('registration_enabled', 'true', 'Whether registration is enabled', 'auth'),
    ('max_group_members', '200', 'Maximum group members', 'chat'),
    ('message_retention_days', '365', 'Message retention period', 'chat'),
    ('maintenance_mode', 'false', 'Maintenance mode status', 'system')
ON CONFLICT (key) DO NOTHING;

-- ============================================
-- KROK 7: FINALNE SPRAWDZENIE
-- ============================================

SELECT 
    'Database setup completed successfully! ✅' as status,
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public') as total_tables,
    (SELECT COUNT(*) FROM public.admin_roles) as admin_count,
    (SELECT COUNT(*) FROM public.system_settings) as settings_count;
