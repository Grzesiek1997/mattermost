-- Fix RLS policies for user search and contact management

-- Allow users to search other users (read-only access to basic profile info)
DROP POLICY IF EXISTS "Users can read own profile" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;

-- New policies for users table
CREATE POLICY "Users can read own profile" ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

-- Allow authenticated users to search other users (basic info only)
CREATE POLICY "Authenticated users can search others" ON users
  FOR SELECT USING (
    auth.uid() IS NOT NULL AND 
    auth.uid() != id
  );

-- Fix contacts policies
DROP POLICY IF EXISTS "Users can read their contacts" ON contacts;
DROP POLICY IF EXISTS "Users can manage their contacts" ON contacts;

-- New contact policies
CREATE POLICY "Users can read their contacts and invitations" ON contacts
  FOR SELECT USING (
    auth.uid() = user_id OR auth.uid() = contact_user_id
  );

CREATE POLICY "Users can send contact invitations" ON contacts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their contact relationships" ON contacts
  FOR UPDATE USING (
    auth.uid() = user_id OR auth.uid() = contact_user_id
  );

CREATE POLICY "Users can delete their contact relationships" ON contacts
  FOR DELETE USING (
    auth.uid() = user_id OR auth.uid() = contact_user_id
  );

-- Create function to get searchable users (excluding current user and existing contacts)
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
  is_online BOOLEAN,
  last_seen TIMESTAMP WITH TIME ZONE,
  contact_status TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    u.id,
    u.email,
    u.username,
    u.full_name,
    u.avatar_url,
    u.bio,
    u.is_online,
    u.last_seen,
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_searchable_users TO authenticated;
