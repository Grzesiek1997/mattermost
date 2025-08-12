-- ChatGPT Comprehensive Chat Fix
-- This script completely rebuilds the chat system with proper RLS policies

-- 0. Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Drop existing problematic policies to start fresh
DROP POLICY IF EXISTS "Users can view all profiles" ON public.users;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
DROP POLICY IF EXISTS "Users can create chats" ON public.chats;
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_participants;
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;

-- 2. Ensure tables exist with correct structure
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT,
  bio TEXT,
  phone TEXT,
  is_online BOOLEAN DEFAULT false,
  last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.chats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by UUID NOT NULL,
  is_direct BOOLEAN DEFAULT true,
  name TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.chat_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  role TEXT DEFAULT 'member',
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE (chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL,
  content TEXT,
  message_type TEXT DEFAULT 'text',
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Create test user creation function
CREATE OR REPLACE FUNCTION public.test_user_creation(p_user_id UUID, p_email TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _id UUID;
BEGIN
  SELECT id INTO _id FROM users WHERE id = p_user_id;
  IF NOT FOUND THEN
    INSERT INTO users (id, email, created_at) VALUES (p_user_id, p_email, NOW());
    RETURN p_user_id;
  END IF;
  RETURN _id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.test_user_creation(UUID, TEXT) TO authenticated;

-- 4. Create direct chat function with SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.create_direct_chat_with_members(user1 UUID, user2 UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  chat_id UUID;
BEGIN
  -- Check if direct chat already exists between these users
  SELECT c.id INTO chat_id
  FROM chats c
  JOIN chat_members m1 ON m1.chat_id = c.id AND m1.user_id = user1
  JOIN chat_members m2 ON m2.chat_id = c.id AND m2.user_id = user2
  WHERE c.is_direct = true
  LIMIT 1;

  IF chat_id IS NOT NULL THEN
    RETURN chat_id;
  END IF;

  -- Create new direct chat
  INSERT INTO chats (created_by, is_direct) VALUES (user1, true) RETURNING id INTO chat_id;
  
  -- Add both users as members
  INSERT INTO chat_members (chat_id, user_id) VALUES (chat_id, user1);
  INSERT INTO chat_members (chat_id, user_id) VALUES (chat_id, user2);

  RETURN chat_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members(UUID, UUID) TO authenticated;

-- 5. Create searchable users function
CREATE OR REPLACE FUNCTION public.get_searchable_users(search_term TEXT DEFAULT '')
RETURNS TABLE(
  id UUID,
  email TEXT,
  username TEXT,
  full_name TEXT,
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
    u.email,
    u.username,
    u.full_name,
    u.avatar_url
  FROM users u
  WHERE 
    u.id != auth.uid() AND
    (
      search_term = '' OR
      u.username ILIKE '%' || search_term || '%' OR
      u.full_name ILIKE '%' || search_term || '%' OR
      u.email ILIKE '%' || search_term || '%'
    )
  ORDER BY u.full_name, u.username
  LIMIT 50;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_searchable_users(TEXT) TO authenticated;

-- 6. Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- 7. Create simple RLS policies without recursion

-- Users policies
CREATE POLICY "users_insert_own" ON public.users
FOR INSERT USING (auth.role() = 'authenticated')
WITH CHECK (auth.uid() = id);

CREATE POLICY "users_update_own" ON public.users
FOR UPDATE USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

CREATE POLICY "users_select_public" ON public.users
FOR SELECT USING (true);

-- Chats policies
CREATE POLICY "chats_select_for_members" ON public.chats
FOR SELECT USING (
  EXISTS (SELECT 1 FROM chat_members cm WHERE cm.chat_id = chats.id AND cm.user_id = auth.uid())
);

CREATE POLICY "chats_insert_authenticated" ON public.chats
FOR INSERT USING (auth.role() = 'authenticated')
WITH CHECK (auth.role() = 'authenticated');

-- Chat members policies
CREATE POLICY "chat_members_select_own" ON public.chat_members
FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "chat_members_insert_self" ON public.chat_members
FOR INSERT USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Messages policies
CREATE POLICY "messages_select_for_members" ON public.messages
FOR SELECT USING (
  EXISTS (SELECT 1 FROM chat_members cm WHERE cm.chat_id = messages.chat_id AND cm.user_id = auth.uid())
);

CREATE POLICY "messages_insert_authenticated" ON public.messages
FOR INSERT USING (
  EXISTS (SELECT 1 FROM chat_members cm WHERE cm.chat_id = messages.chat_id AND cm.user_id = auth.uid())
)
WITH CHECK (sender_id = auth.uid());

-- 8. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_chat_members_chat_id ON public.chat_members(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_user_id ON public.chat_members(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON public.messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at DESC);

-- 9. Test the functions
SELECT 'Database setup complete. Functions created:' as status;
SELECT proname FROM pg_proc WHERE proname IN ('test_user_creation', 'create_direct_chat_with_members', 'get_searchable_users');
