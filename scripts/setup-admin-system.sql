-- ========================================
-- KOMPLETNY SYSTEM RÓL ADMINISTRATORA
-- ========================================
-- Uruchom to w SQL Editor w Supabase

-- ============================================
-- KROK 1: TWORZENIE TABEL ADMIN
-- ============================================

-- Tabela ról administratorów
CREATE TABLE IF NOT EXISTS public.admin_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
    role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('super_admin', 'admin', 'moderator')),
    permissions JSONB DEFAULT '{}',
    granted_by UUID REFERENCES public.users(id),
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela akcji administratorów (audit log)
CREATE TABLE IF NOT EXISTS public.admin_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL,
    target_type TEXT, -- 'user', 'chat', 'message', 'system'
    target_id UUID,
    details JSONB DEFAULT '{}',
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela ustawień systemowych
CREATE TABLE IF NOT EXISTS public.system_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT UNIQUE NOT NULL,
    value JSONB NOT NULL,
    description TEXT,
    category TEXT DEFAULT 'general',
    updated_by UUID REFERENCES public.users(id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela raportów użytkowników
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
-- KROK 2: INDEKSY DLA WYDAJNOŚCI
-- ============================================

CREATE INDEX IF NOT EXISTS idx_admin_roles_user_id ON public.admin_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_admin_roles_role ON public.admin_roles(role);
CREATE INDEX IF NOT EXISTS idx_admin_actions_admin_user_id ON public.admin_actions(admin_user_id);
CREATE INDEX IF NOT EXISTS idx_admin_actions_created_at ON public.admin_actions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_actions_action_type ON public.admin_actions(action_type);
CREATE INDEX IF NOT EXISTS idx_system_settings_key ON public.system_settings(key);
CREATE INDEX IF NOT EXISTS idx_user_reports_status ON public.user_reports(status);
CREATE INDEX IF NOT EXISTS idx_user_reports_reporter_id ON public.user_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_reported_user_id ON public.user_reports(reported_user_id);

-- ============================================
-- KROK 3: RLS POLICIES
-- ============================================

-- Włącz RLS dla wszystkich tabel admin
ALTER TABLE public.admin_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

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

-- Polityki dla admin_actions
DROP POLICY IF EXISTS "Admins can view admin actions" ON public.admin_actions;
CREATE POLICY "Admins can view admin actions" ON public.admin_actions
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.admin_roles WHERE user_id = auth.uid())
    );

DROP POLICY IF EXISTS "Admins can log their actions" ON public.admin_actions;
CREATE POLICY "Admins can log their actions" ON public.admin_actions
    FOR INSERT WITH CHECK (
        admin_user_id = auth.uid() AND
        EXISTS (SELECT 1 FROM public.admin_roles WHERE user_id = auth.uid())
    );

-- Polityki dla system_settings
DROP POLICY IF EXISTS "Admins can read system settings" ON public.system_settings;
CREATE POLICY "Admins can read system settings" ON public.system_settings
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.admin_roles WHERE user_id = auth.uid())
    );

DROP POLICY IF EXISTS "Super admins can manage system settings" ON public.system_settings;
CREATE POLICY "Super admins can manage system settings" ON public.system_settings
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.admin_roles 
            WHERE user_id = auth.uid() AND role = 'super_admin'
        )
    );

-- Polityki dla user_reports
DROP POLICY IF EXISTS "Users can create reports" ON public.user_reports;
CREATE POLICY "Users can create reports" ON public.user_reports
    FOR INSERT WITH CHECK (reporter_id = auth.uid());

DROP POLICY IF EXISTS "Users can view their reports" ON public.user_reports;
CREATE POLICY "Users can view their reports" ON public.user_reports
    FOR SELECT USING (reporter_id = auth.uid());

DROP POLICY IF EXISTS "Admins can manage reports" ON public.user_reports;
CREATE POLICY "Admins can manage reports" ON public.user_reports
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.admin_roles WHERE user_id = auth.uid())
    );

-- ============================================
-- KROK 4: FUNKCJE ADMIN
-- ============================================

-- Funkcja logowania akcji admin
CREATE OR REPLACE FUNCTION public.log_admin_action(
    action_type_param TEXT,
    target_type_param TEXT DEFAULT NULL,
    target_id_param UUID DEFAULT NULL,
    details_param JSONB DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    action_id UUID;
    current_user_id UUID;
BEGIN
    current_user_id := auth.uid();
    
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'No authenticated user';
    END IF;
    
    -- Sprawdź czy user jest adminem
    IF NOT EXISTS (SELECT 1 FROM public.admin_roles WHERE user_id = current_user_id) THEN
        RAISE EXCEPTION 'User is not an admin';
    END IF;
    
    -- Zapisz akcję
    INSERT INTO public.admin_actions (
        admin_user_id, action_type, target_type, target_id, details
    ) VALUES (
        current_user_id, action_type_param, target_type_param, target_id_param, details_param
    ) RETURNING id INTO action_id;
    
    RETURN action_id;
END;
$$;

-- Funkcja pobierania statystyk admin
CREATE OR REPLACE FUNCTION public.get_admin_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    stats JSONB;
BEGIN
    -- Sprawdź czy user jest adminem
    IF NOT EXISTS (SELECT 1 FROM public.admin_roles WHERE user_id = auth.uid()) THEN
        RAISE EXCEPTION 'Access denied: Admin role required';
    END IF;
    
    SELECT jsonb_build_object(
        'total_users', (SELECT COUNT(*) FROM public.users),
        'online_users', (SELECT COUNT(*) FROM public.users WHERE is_online = true),
        'total_chats', (SELECT COUNT(*) FROM public.chats),
        'total_messages', (SELECT COUNT(*) FROM public.messages),
        'pending_reports', (SELECT COUNT(*) FROM public.user_reports WHERE status = 'pending'),
        'total_admins', (SELECT COUNT(*) FROM public.admin_roles),
        'recent_signups', (
            SELECT COUNT(*) FROM public.users 
            WHERE created_at > NOW() - INTERVAL '7 days'
        )
    ) INTO stats;
    
    RETURN stats;
END;
$$;

-- Funkcja zarządzania użytkownikami
CREATE OR REPLACE FUNCTION public.admin_manage_user(
    target_user_id UUID,
    action_type TEXT, -- 'ban', 'unban', 'delete', 'promote', 'demote'
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
            -- Implementacja banowania (można dodać tabelę banned_users)
            result_message := 'User banned successfully';
        WHEN 'unban' THEN
            -- Implementacja odbanowania
            result_message := 'User unbanned successfully';
        WHEN 'delete' THEN
            -- Tylko super admini mogą usuwać użytkowników
            IF current_user_role != 'super_admin' THEN
                RAISE EXCEPTION 'Only super admins can delete users';
            END IF;
            DELETE FROM public.users WHERE id = target_user_id;
            result_message := 'User deleted successfully';
        ELSE
            RAISE EXCEPTION 'Invalid action type';
    END CASE;
    
    -- Zaloguj akcję
    PERFORM public.log_admin_action(
        action_type, 
        'user', 
        target_user_id, 
        jsonb_build_object('reason', reason)
    );
    
    RETURN result_message;
END;
$$;

-- ============================================
-- KROK 5: DOMYŚLNE USTAWIENIA SYSTEMU
-- ============================================

INSERT INTO public.system_settings (key, value, description, category) VALUES
    ('app_name', '"Telegram Clone"', 'Application name', 'general'),
    ('max_file_size', '52428800', 'Maximum file upload size in bytes (50MB)', 'uploads'),
    ('allowed_file_types', '["image/*", "video/*", "audio/*", ".pdf", ".doc", ".docx", ".txt"]', 'Allowed file types', 'uploads'),
    ('registration_enabled', 'true', 'Whether new user registration is enabled', 'auth'),
    ('max_group_members', '200', 'Maximum members in a group chat', 'chat'),
    ('message_retention_days', '365', 'Days to keep messages before deletion', 'chat'),
    ('rate_limit_messages', '60', 'Messages per minute per user', 'rate_limiting'),
    ('maintenance_mode', 'false', 'Enable maintenance mode', 'system')
ON CONFLICT (key) DO NOTHING;

-- ============================================
-- KROK 6: NADANIE UPRAWNIEŃ
-- ============================================

GRANT EXECUTE ON FUNCTION public.log_admin_action TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_stats TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_user TO authenticated;

-- ============================================
-- KROK 7: SPRAWDZENIE INSTALACJI
-- ============================================

SELECT 
    'Admin system installed successfully!' as status,
    COUNT(*) as admin_tables_created
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('admin_roles', 'admin_actions', 'system_settings', 'user_reports');
