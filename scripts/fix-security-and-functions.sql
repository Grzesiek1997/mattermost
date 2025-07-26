-- ========================================
-- NAPRAWA BŁĘDÓW BEZPIECZEŃSTWA SUPABASE
-- ========================================

-- 1. NAPRAW FUNKCJE Z SEARCH_PATH (bezpieczeństwo)
CREATE OR REPLACE FUNCTION update_user_last_seen()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_online = true AND OLD.is_online = false THEN
    NEW.last_seen = NOW();
  END IF;
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION update_chat_last_message()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE chats 
  SET last_message_at = NEW.created_at, updated_at = NOW()
  WHERE id = NEW.chat_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION add_chat_creator_as_owner()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO chat_members (chat_id, user_id, role, can_send_messages, can_add_members, can_delete_messages)
  VALUES (NEW.id, NEW.created_by, 'owner', true, true, true);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION get_searchable_users(
  search_query TEXT,
  current_user_id UUID,
  result_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
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
    COALESCE(c.status, 'none') as contact_status
  FROM users u
  LEFT JOIN contacts c ON (
    (c.user_id = current_user_id AND c.contact_user_id = u.id) OR
    (c.contact_user_id = current_user_id AND c.user_id = u.id)
  )
  WHERE 
    u.id != current_user_id
    AND (
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

-- 2. DODAJ TABELE ADMIN SYSTEM
CREATE TABLE IF NOT EXISTS admin_users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  role TEXT CHECK (role IN ('super_admin', 'admin', 'moderator')) DEFAULT 'admin',
  permissions JSONB DEFAULT '{}',
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS admin_actions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_id UUID REFERENCES admin_users(id),
  action_type TEXT NOT NULL,
  target_type TEXT, -- 'user', 'chat', 'message', etc.
  target_id UUID,
  details JSONB DEFAULT '{}',
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS system_settings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,
  value JSONB NOT NULL,
  description TEXT,
  updated_by UUID REFERENCES admin_users(id),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_reports (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  reporter_id UUID REFERENCES users(id),
  reported_user_id UUID REFERENCES users(id),
  reported_message_id UUID REFERENCES messages(id),
  report_type TEXT CHECK (report_type IN ('spam', 'harassment', 'inappropriate', 'fake', 'other')),
  description TEXT,
  status TEXT CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')) DEFAULT 'pending',
  reviewed_by UUID REFERENCES admin_users(id),
  reviewed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. DODAJ INDEKSY
CREATE INDEX IF NOT EXISTS idx_admin_users_user_id ON admin_users(user_id);
CREATE INDEX IF NOT EXISTS idx_admin_actions_admin_id ON admin_actions(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_actions_created_at ON admin_actions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_reports_status ON user_reports(status);
CREATE INDEX IF NOT EXISTS idx_user_reports_reported_user_id ON user_reports(reported_user_id);

-- 4. RLS POLICIES DLA ADMIN
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_reports ENABLE ROW LEVEL SECURITY;

-- Admin users policies
CREATE POLICY "Super admins can manage all admin users" ON admin_users
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM admin_users au 
      WHERE au.user_id = auth.uid() AND au.role = 'super_admin'
    )
  );

CREATE POLICY "Admins can read admin users" ON admin_users
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM admin_users au 
      WHERE au.user_id = auth.uid()
    )
  );

-- Admin actions policies
CREATE POLICY "Admins can read all actions" ON admin_actions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM admin_users au 
      WHERE au.user_id = auth.uid()
    )
  );

CREATE POLICY "Admins can insert their actions" ON admin_actions
  FOR INSERT WITH CHECK (
    admin_id IN (
      SELECT id FROM admin_users WHERE user_id = auth.uid()
    )
  );

-- System settings policies
CREATE POLICY "Admins can read system settings" ON system_settings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM admin_users au 
      WHERE au.user_id = auth.uid()
    )
  );

CREATE POLICY "Super admins can manage system settings" ON system_settings
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM admin_users au 
      WHERE au.user_id = auth.uid() AND au.role = 'super_admin'
    )
  );

-- User reports policies
CREATE POLICY "Users can create reports" ON user_reports
  FOR INSERT WITH CHECK (reporter_id = auth.uid());

CREATE POLICY "Users can read their own reports" ON user_reports
  FOR SELECT USING (reporter_id = auth.uid());

CREATE POLICY "Admins can read all reports" ON user_reports
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM admin_users au 
      WHERE au.user_id = auth.uid()
    )
  );

CREATE POLICY "Admins can update reports" ON user_reports
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM admin_users au 
      WHERE au.user_id = auth.uid()
    )
  );

-- 5. FUNKCJE ADMIN
CREATE OR REPLACE FUNCTION is_admin(user_uuid UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM admin_users 
    WHERE user_id = user_uuid
  );
END;
$$;

CREATE OR REPLACE FUNCTION get_admin_role(user_uuid UUID DEFAULT auth.uid())
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  admin_role TEXT;
BEGIN
  SELECT role INTO admin_role
  FROM admin_users 
  WHERE user_id = user_uuid;
  
  RETURN COALESCE(admin_role, 'user');
END;
$$;

CREATE OR REPLACE FUNCTION log_admin_action(
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
  admin_record admin_users%ROWTYPE;
  action_id UUID;
BEGIN
  -- Get admin record
  SELECT * INTO admin_record
  FROM admin_users 
  WHERE user_id = auth.uid();
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User is not an admin';
  END IF;
  
  -- Insert action log
  INSERT INTO admin_actions (
    admin_id, action_type, target_type, target_id, details
  ) VALUES (
    admin_record.id, action_type_param, target_type_param, target_id_param, details_param
  ) RETURNING id INTO action_id;
  
  RETURN action_id;
END;
$$;

-- 6. USUŃ TESTOWYCH UŻYTKOWNIKÓW (BEZPIECZEŃSTWO!)
DELETE FROM users WHERE email LIKE '%@test.com';

-- 7. DODAJ DOMYŚLNE USTAWIENIA SYSTEMU
INSERT INTO system_settings (key, value, description) VALUES
  ('app_name', '"Telegram Clone"', 'Application name'),
  ('max_file_size', '52428800', 'Maximum file upload size in bytes (50MB)'),
  ('allowed_file_types', '["image/*", "video/*", "audio/*", ".pdf", ".doc", ".docx", ".txt"]', 'Allowed file types for upload'),
  ('registration_enabled', 'true', 'Whether new user registration is enabled'),
  ('max_group_members', '200', 'Maximum number of members in a group'),
  ('message_retention_days', '365', 'Number of days to keep messages'),
  ('rate_limit_messages_per_minute', '60', 'Rate limit for messages per user per minute')
ON CONFLICT (key) DO NOTHING;

-- Grant permissions
GRANT EXECUTE ON FUNCTION is_admin TO authenticated;
GRANT EXECUTE ON FUNCTION get_admin_role TO authenticated;
GRANT EXECUTE ON FUNCTION log_admin_action TO authenticated;
GRANT EXECUTE ON FUNCTION get_searchable_users TO authenticated;
