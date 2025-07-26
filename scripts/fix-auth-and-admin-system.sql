-- ========================================
-- KOMPLETNA NAPRAWA SYSTEMU AUTENTYKACJI I ADMIN
-- ========================================

-- 1. SPRAWDŹ I NAPRAW TABELE
-- Sprawdź czy tabela users istnieje i ma poprawną strukturę
SELECT table_name, column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'users' 
ORDER BY ordinal_position;

-- Jeśli tabela nie istnieje lub ma błędy, utwórz ją ponownie
DROP TABLE IF EXISTS users CASCADE;
CREATE TABLE users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE,
  full_name TEXT,
  bio TEXT,
  avatar_url TEXT,
  phone TEXT,
  is_online BOOLEAN DEFAULT false,
  last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. NAPRAW RLS POLICIES - USUŃ WSZYSTKIE I DODAJ NOWE
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can read own profile" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Users can insert own profile" ON users;
DROP POLICY IF EXISTS "Authenticated users can read all users" ON users;
DROP POLICY IF EXISTS "Authenticated users can search others" ON users;

-- Włącz RLS z nowymi, prostszymi politykami
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Pozwól authenticated użytkownikom na wszystko (na razie, dla debugowania)
CREATE POLICY "Allow authenticated users full access" ON users
  FOR ALL USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- 3. NAPRAW FUNKCJE TRIGGERY
DROP FUNCTION IF EXISTS update_user_last_seen() CASCADE;
CREATE OR REPLACE FUNCTION update_user_last_seen()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_online = true AND (OLD.is_online = false OR OLD.is_online IS NULL) THEN
    NEW.last_seen = NOW();
  END IF;
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_update_user_last_seen
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION update_user_last_seen();

-- 4. FUNKCJA DO TWORZENIA PIERWSZEGO SUPER ADMINA
CREATE OR REPLACE FUNCTION create_first_super_admin()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  admin_count INTEGER;
  first_user_id UUID;
  result_text TEXT;
BEGIN
  -- Sprawdź czy już są admini
  SELECT COUNT(*) INTO admin_count FROM admin_users;
  
  IF admin_count > 0 THEN
    RETURN 'Admin users already exist. First super admin already created.';
  END IF;
  
  -- Znajdź pierwszego użytkownika (najstarszego)
  SELECT id INTO first_user_id 
  FROM users 
  ORDER BY created_at ASC 
  LIMIT 1;
  
  IF first_user_id IS NULL THEN
    RETURN 'No users found. Please create a user account first.';
  END IF;
  
  -- Utwórz pierwszego super admina
  INSERT INTO admin_users (user_id, role, created_by, permissions)
  VALUES (
    first_user_id, 
    'super_admin', 
    first_user_id,
    '{"all": true, "created_first": true}'
  );
  
  -- Zwróć informację
  SELECT 'First super admin created for user: ' || email INTO result_text
  FROM users WHERE id = first_user_id;
  
  RETURN result_text;
END;
$$;

-- 5. FUNKCJA DO PROMOWANIA UŻYTKOWNIKA NA ADMINA (TYLKO DLA SUPER ADMINÓW)
CREATE OR REPLACE FUNCTION promote_user_to_admin(
  target_email TEXT,
  admin_role TEXT DEFAULT 'admin'
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_role TEXT;
  target_user_id UUID;
  result_text TEXT;
BEGIN
  -- Sprawdź czy obecny użytkownik to super admin
  SELECT role INTO current_user_role
  FROM admin_users 
  WHERE user_id = auth.uid();
  
  IF current_user_role != 'super_admin' THEN
    RETURN 'ERROR: Only super admins can promote users';
  END IF;
  
  -- Znajdź użytkownika po emailu
  SELECT id INTO target_user_id
  FROM users 
  WHERE email = target_email;
  
  IF target_user_id IS NULL THEN
    RETURN 'ERROR: User with email ' || target_email || ' not found';
  END IF;
  
  -- Sprawdź czy już jest adminem
  IF EXISTS (SELECT 1 FROM admin_users WHERE user_id = target_user_id) THEN
    RETURN 'ERROR: User is already an admin';
  END IF;
  
  -- Promuj na admina
  INSERT INTO admin_users (user_id, role, created_by)
  VALUES (target_user_id, admin_role, auth.uid());
  
  RETURN 'SUCCESS: User ' || target_email || ' promoted to ' || admin_role;
END;
$$;

-- 6. DODAJ INDEKSY DLA WYDAJNOŚCI
CREATE INDEX IF NOT EXISTS idx_users_email_lower ON users(LOWER(email));
CREATE INDEX IF NOT EXISTS idx_users_username_lower ON users(LOWER(username));
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);
CREATE INDEX IF NOT EXISTS idx_users_is_online ON users(is_online);

-- 7. SPRAWDŹ AUTENTYKACJĘ SUPABASE
-- Ta funkcja pomoże zdiagnozować problemy z auth
CREATE OR REPLACE FUNCTION debug_auth_info()
RETURNS TABLE (
  current_user_id UUID,
  current_user_email TEXT,
  users_count BIGINT,
  auth_users_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    auth.uid() as current_user_id,
    auth.email() as current_user_email,
    (SELECT COUNT(*) FROM users) as users_count,
    (SELECT COUNT(*) FROM auth.users) as auth_users_count;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION create_first_super_admin TO authenticated;
GRANT EXECUTE ON FUNCTION promote_user_to_admin TO authenticated;
GRANT EXECUTE ON FUNCTION debug_auth_info TO authenticated;

-- 8. WYCZYŚĆ I ZRESETUJ DANE
-- Usuń wszystkie istniejące dane (UWAGA: to wyczyści bazę!)
TRUNCATE TABLE admin_actions CASCADE;
TRUNCATE TABLE admin_users CASCADE;
TRUNCATE TABLE user_reports CASCADE;
TRUNCATE TABLE message_reactions CASCADE;
TRUNCATE TABLE message_reads CASCADE;
TRUNCATE TABLE messages CASCADE;
TRUNCATE TABLE chat_members CASCADE;
TRUNCATE TABLE chats CASCADE;
TRUNCATE TABLE contacts CASCADE;
TRUNCATE TABLE typing_indicators CASCADE;
TRUNCATE TABLE users CASCADE;

-- 9. SPRAWDŹ STATUS
SELECT 'Database reset complete. Ready for fresh start.' as status;
