-- First, let's check what we have and fix any issues

-- Check if we have any users
SELECT COUNT(*) as user_count FROM users;

-- Check current RLS policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename IN ('users', 'contacts');

-- Drop all existing RLS policies for users to start fresh
DROP POLICY IF EXISTS "Users can read own profile" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Authenticated users can search others" ON users;

-- Create new, more permissive policies for testing
CREATE POLICY "Users can read all profiles" ON users
  FOR SELECT USING (true);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Temporarily disable RLS for testing (we'll re-enable it later)
ALTER TABLE users DISABLE ROW LEVEL SECURITY;

-- Insert some test users for searching
INSERT INTO users (id, email, username, full_name, bio, is_online, avatar_url) VALUES
  ('11111111-1111-1111-1111-111111111111', 'john.doe@test.com', 'johndoe', 'John Doe', 'Software Developer', true, '/placeholder.svg'),
  ('22222222-2222-2222-2222-222222222222', 'jane.smith@test.com', 'janesmith', 'Jane Smith', 'UI/UX Designer', false, '/placeholder.svg'),
  ('33333333-3333-3333-3333-333333333333', 'mike.wilson@test.com', 'mikewilson', 'Mike Wilson', 'Product Manager', true, '/placeholder.svg'),
  ('44444444-4444-4444-4444-444444444444', 'sarah.johnson@test.com', 'sarahj', 'Sarah Johnson', 'Marketing Specialist', false, '/placeholder.svg'),
  ('55555555-5555-5555-5555-555555555555', 'alex.brown@test.com', 'alexbrown', 'Alex Brown', 'Data Scientist', true, '/placeholder.svg')
ON CONFLICT (id) DO UPDATE SET
  email = EXCLUDED.email,
  username = EXCLUDED.username,
  full_name = EXCLUDED.full_name,
  bio = EXCLUDED.bio,
  is_online = EXCLUDED.is_online,
  avatar_url = EXCLUDED.avatar_url;

-- Re-enable RLS with more permissive policies
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Create a simple policy that allows authenticated users to read all user profiles
CREATE POLICY "Authenticated users can read all users" ON users
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Verify the data was inserted
SELECT id, email, username, full_name FROM users ORDER BY created_at DESC LIMIT 10;

-- Test the search function
SELECT * FROM get_searchable_users('john', '11111111-1111-1111-1111-111111111111', 10);
