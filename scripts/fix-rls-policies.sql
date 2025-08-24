-- ========================================
-- COMPREHENSIVE RLS FIX FOR PROFILES TABLE
-- ========================================

-- 1. Fix profiles table (the user mentioned they have this table)
ALTER TABLE IF EXISTS profiles DISABLE ROW LEVEL SECURITY;

-- Drop all existing policies on profiles
DROP POLICY IF EXISTS "Allow authenticated users full access" ON profiles;
DROP POLICY IF EXISTS "Users can read own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;
DROP POLICY IF EXISTS "Authenticated users can read all profiles" ON profiles;
DROP POLICY IF EXISTS "Authenticated users can search others" ON profiles;

-- Enable RLS with proper policies
ALTER TABLE IF EXISTS profiles ENABLE ROW LEVEL SECURITY;

-- Policy for INSERT - allow profile creation during registration
CREATE POLICY "Allow profile creation" ON profiles
  FOR INSERT 
  WITH CHECK (
    -- Allow if user ID matches auth.uid() (during registration)
    auth.uid() = id
  );

-- Policy for SELECT - allow reading all profiles (needed for search)
CREATE POLICY "Allow reading profiles" ON profiles
  FOR SELECT 
  USING (
    -- Allow authenticated users to read all profiles
    auth.uid() IS NOT NULL
  );

-- Policy for UPDATE - allow updating own profile
CREATE POLICY "Allow updating own profile" ON profiles
  FOR UPDATE 
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Policy for DELETE - only own profile (optional)
CREATE POLICY "Allow deleting own profile" ON profiles
  FOR DELETE 
  USING (auth.uid() = id);

-- 2. Fix users table if it exists (legacy)
ALTER TABLE IF EXISTS users DISABLE ROW LEVEL SECURITY;

-- Drop all existing policies on users
DROP POLICY IF EXISTS "Allow authenticated users full access" ON users;
DROP POLICY IF EXISTS "Users can read own profile" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Users can insert own profile" ON users;
DROP POLICY IF EXISTS "Authenticated users can read all users" ON users;
DROP POLICY IF EXISTS "Authenticated users can search others" ON users;

-- Enable RLS with proper policies
ALTER TABLE IF EXISTS users ENABLE ROW LEVEL SECURITY;

-- Same policies for users table
CREATE POLICY "Allow user creation" ON users
  FOR INSERT 
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Allow reading users" ON users
  FOR SELECT 
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "Allow updating own user" ON users
  FOR UPDATE 
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- 3. Fix room_participants infinite recursion
ALTER TABLE IF EXISTS room_participants DISABLE ROW LEVEL SECURITY;

-- Drop problematic policies
DROP POLICY IF EXISTS "Users can access rooms they participate in" ON room_participants;
DROP POLICY IF EXISTS "Users can join rooms" ON room_participants;
DROP POLICY IF EXISTS "Users can leave rooms" ON room_participants;

-- Enable with simple policies
ALTER TABLE IF EXISTS room_participants ENABLE ROW LEVEL SECURITY;

-- Simple policy - users can see their own participations
CREATE POLICY "Users can see own participations" ON room_participants
  FOR SELECT 
  USING (user_id = auth.uid());

-- Users can join rooms (insert)
CREATE POLICY "Users can join rooms" ON room_participants
  FOR INSERT 
  WITH CHECK (user_id = auth.uid());

-- Users can leave rooms (delete)
CREATE POLICY "Users can leave rooms" ON room_participants
  FOR DELETE 
  USING (user_id = auth.uid());

-- 4. Fix friendships table relationships
ALTER TABLE IF EXISTS friendships DISABLE ROW LEVEL SECURITY;

-- Drop existing policies
DROP POLICY IF EXISTS "Users can see their friendships" ON friendships;
DROP POLICY IF EXISTS "Users can create friendships" ON friendships;

-- Enable with simple policies
ALTER TABLE IF EXISTS friendships ENABLE ROW LEVEL SECURITY;

-- Users can see friendships where they are involved
CREATE POLICY "Users can see own friendships" ON friendships
  FOR SELECT 
  USING (user_id = auth.uid() OR friend_id = auth.uid());

-- Users can create friendships
CREATE POLICY "Users can create friendships" ON friendships
  FOR INSERT 
  WITH CHECK (user_id = auth.uid());

-- 5. Fix friend_requests table
ALTER TABLE IF EXISTS friend_requests DISABLE ROW LEVEL SECURITY;

-- Drop existing policies
DROP POLICY IF EXISTS "Users can see their friend requests" ON friend_requests;
DROP POLICY IF EXISTS "Users can create friend requests" ON friend_requests;

-- Enable with simple policies
ALTER TABLE IF EXISTS friend_requests ENABLE ROW LEVEL SECURITY;

-- Users can see requests they sent or received
CREATE POLICY "Users can see own friend requests" ON friend_requests
  FOR SELECT 
  USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Users can create friend requests
CREATE POLICY "Users can create friend requests" ON friend_requests
  FOR INSERT 
  WITH CHECK (sender_id = auth.uid());

-- Users can update requests they received (accept/reject)
CREATE POLICY "Users can respond to friend requests" ON friend_requests
  FOR UPDATE 
  USING (receiver_id = auth.uid())
  WITH CHECK (receiver_id = auth.uid());

-- 6. Create essential RPC functions
CREATE OR REPLACE FUNCTION get_user_profile(user_id UUID)
RETURNS TABLE(
  id UUID,
  username TEXT,
  full_name TEXT,
  bio TEXT,
  avatar_url TEXT,
  status TEXT,
  last_seen TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.username,
    p.full_name,
    p.bio,
    p.avatar_url,
    p.status,
    p.last_seen,
    p.created_at,
    p.updated_at
  FROM profiles p
  WHERE p.id = user_id;
END;
$$;

CREATE OR REPLACE FUNCTION create_user_profile(
  user_id UUID,
  user_email TEXT,
  user_username TEXT DEFAULT NULL,
  user_full_name TEXT DEFAULT NULL
)
RETURNS TABLE(
  id UUID,
  username TEXT,
  full_name TEXT,
  bio TEXT,
  avatar_url TEXT,
  status TEXT,
  last_seen TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  final_username TEXT;
  final_full_name TEXT;
BEGIN
  -- Set defaults
  final_username := COALESCE(user_username, split_part(user_email, '@', 1));
  final_full_name := COALESCE(user_full_name, 'User');
  
  -- Insert or update profile
  INSERT INTO profiles (
    id, 
    username, 
    full_name, 
    bio,
    avatar_url,
    status,
    last_seen,
    created_at,
    updated_at
  ) VALUES (
    user_id,
    final_username,
    final_full_name,
    NULL,
    NULL,
    'online',
    NOW(),
    NOW(),
    NOW()
  ) 
  ON CONFLICT (id) DO UPDATE SET
    username = EXCLUDED.username,
    full_name = EXCLUDED.full_name,
    status = 'online',
    last_seen = NOW(),
    updated_at = NOW()
  RETURNING 
    profiles.id,
    profiles.username,
    profiles.full_name,
    profiles.bio,
    profiles.avatar_url,
    profiles.status,
    profiles.last_seen,
    profiles.created_at,
    profiles.updated_at;
    
  RETURN;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_user_profile TO authenticated, anon;
GRANT EXECUTE ON FUNCTION create_user_profile TO authenticated, anon;

-- 7. Test function
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
  test_user_id := gen_random_uuid();
  
  BEGIN
    INSERT INTO profiles (id, username, full_name, status, last_seen, created_at, updated_at)
    VALUES (test_user_id, test_username, 'Test User', 'online', NOW(), NOW(), NOW());
    
    result_text := 'SUCCESS: Test user created with ID: ' || test_user_id;
  EXCEPTION WHEN OTHERS THEN
    result_text := 'ERROR: ' || SQLERRM;
  END;
  
  -- Cleanup
  DELETE FROM profiles WHERE id = test_user_id;
  
  RETURN result_text;
END;
$$;

GRANT EXECUTE ON FUNCTION test_user_creation TO authenticated, anon;

-- 8. Display summary
SELECT 'RLS policies fixed successfully. All tables should now work properly.' as status;
