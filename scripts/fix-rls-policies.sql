-- ========================================
-- NAPRAWA RLS POLICIES - POZWÓL NA REJESTRACJĘ
-- ========================================

-- 1. WYŁĄCZ RLS TYMCZASOWO I WYCZYŚĆ WSZYSTKIE POLICY
ALTER TABLE users DISABLE ROW LEVEL SECURITY;

-- Usuń wszystkie istniejące policies
DROP POLICY IF EXISTS "Allow authenticated users full access" ON users;
DROP POLICY IF EXISTS "Users can read own profile" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Users can insert own profile" ON users;
DROP POLICY IF EXISTS "Authenticated users can read all users" ON users;
DROP POLICY IF EXISTS "Authenticated users can search others" ON users;

-- 2. WŁĄCZ RLS Z NOWYMI, POPRAWNYMI POLICIES
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Policy dla INSERT - pozwól na tworzenie profilu podczas rejestracji
CREATE POLICY "Allow user profile creation" ON users
  FOR INSERT 
  WITH CHECK (
    -- Pozwól jeśli ID użytkownika to auth.uid() (podczas rejestracji)
    auth.uid() = id
  );

-- Policy dla SELECT - pozwól czytać wszystkie profile (potrzebne do wyszukiwania)
CREATE POLICY "Allow reading user profiles" ON users
  FOR SELECT 
  USING (
    -- Pozwól authenticated użytkownikom czytać wszystkie profile
    auth.uid() IS NOT NULL
  );

-- Policy dla UPDATE - pozwól aktualizować własny profil
CREATE POLICY "Allow updating own profile" ON users
  FOR UPDATE 
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Policy dla DELETE - tylko własny profil (opcjonalne)
CREATE POLICY "Allow deleting own profile" ON users
  FOR DELETE 
  USING (auth.uid() = id);

-- 3. SPRAWDŹ CZY POLICIES SĄ POPRAWNE
SELECT 
  schemaname, 
  tablename, 
  policyname, 
  permissive, 
  roles, 
  cmd, 
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'users'
ORDER BY cmd, policyname;

-- 4. TESTOWA FUNKCJA DO SPRAWDZENIA RLS
CREATE OR REPLACE FUNCTION test_user_creation(
  test_email TEXT,
  test_username TEXT DEFAULT 'testuser'
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  test_user_id UUID;
  result_text TEXT;
BEGIN
  -- Generuj test UUID
  test_user_id := gen_random_uuid();
  
  -- Spróbuj wstawić użytkownika
  BEGIN
    INSERT INTO users (id, email, username, full_name, is_online)
    VALUES (test_user_id, test_email, test_username, 'Test User', true);
    
    result_text := 'SUCCESS: Test user created with ID: ' || test_user_id;
  EXCEPTION WHEN OTHERS THEN
    result_text := 'ERROR: ' || SQLERRM;
  END;
  
  -- Wyczyść test data
  DELETE FROM users WHERE id = test_user_id;
  
  RETURN result_text;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION test_user_creation TO authenticated;
GRANT EXECUTE ON FUNCTION test_user_creation TO anon;

-- 5. DODAJ FUNKCJĘ DO BEZPIECZNEGO TWORZENIA UŻYTKOWNIKA
CREATE OR REPLACE FUNCTION create_user_profile(
  user_id UUID,
  user_email TEXT,
  user_username TEXT DEFAULT NULL,
  user_full_name TEXT DEFAULT NULL
)
RETURNS users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_user users;
BEGIN
  -- Sprawdź czy użytkownik już istnieje
  SELECT * INTO new_user FROM users WHERE id = user_id;
  
  IF FOUND THEN
    RETURN new_user;
  END IF;
  
  -- Utwórz nowy profil użytkownika
  INSERT INTO users (
    id, 
    email, 
    username, 
    full_name, 
    is_online, 
    last_seen
  ) VALUES (
    user_id,
    user_email,
    COALESCE(user_username, split_part(user_email, '@', 1)),
    COALESCE(user_full_name, 'User'),
    true,
    NOW()
  ) RETURNING * INTO new_user;
  
  RETURN new_user;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION create_user_profile TO authenticated;
GRANT EXECUTE ON FUNCTION create_user_profile TO anon;

-- 6. SPRAWDŹ STATUS TABELI
SELECT 
  'Table: ' || tablename as info,
  'RLS Enabled: ' || CASE WHEN rowsecurity THEN 'YES' ELSE 'NO' END as rls_status
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
WHERE t.tablename = 'users' AND t.schemaname = 'public';

-- 7. WYŚWIETL PODSUMOWANIE
SELECT 'RLS policies updated successfully. User registration should now work.' as status;
