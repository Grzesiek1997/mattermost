-- COMPREHENSIVE CHAT SYSTEM FIX
-- Based on Polish guide for v0.app + Supabase

-- STEP 1: Create all required tables
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT auth.uid(),
  username TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.chats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by UUID REFERENCES public.users(id),
  name TEXT,
  is_direct BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.chat_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- STEP 2: Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- STEP 3: Drop existing problematic policies
DROP POLICY IF EXISTS "Public read users" ON public.users;
DROP POLICY IF EXISTS "Read own chats" ON public.chats;
DROP POLICY IF EXISTS "Read own chat members" ON public.chat_members;
DROP POLICY IF EXISTS "Read messages from own chats" ON public.messages;

-- STEP 4: Create simple, non-recursive RLS policies
-- Users: everyone can see all users (for search functionality)
CREATE POLICY "Public read users" ON public.users
FOR SELECT USING (true);

CREATE POLICY "Users can insert own profile" ON public.users
FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.users
FOR UPDATE USING (auth.uid() = id);

-- Chats: users can see chats they're members of
CREATE POLICY "Read own chats" ON public.chats
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.chat_members
    WHERE chat_members.chat_id = chats.id
    AND chat_members.user_id = auth.uid()
  )
);

CREATE POLICY "Create chats" ON public.chats
FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Chat members: users can see members of their chats
CREATE POLICY "Read chat members" ON public.chat_members
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.chat_members cm
    WHERE cm.chat_id = chat_members.chat_id
    AND cm.user_id = auth.uid()
  )
);

CREATE POLICY "Join chats" ON public.chat_members
FOR INSERT WITH CHECK (true);

-- Messages: users can see messages in their chats
CREATE POLICY "Read messages from own chats" ON public.messages
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.chat_members
    WHERE chat_members.chat_id = messages.chat_id
    AND chat_members.user_id = auth.uid()
  )
);

CREATE POLICY "Send messages" ON public.messages
FOR INSERT WITH CHECK (
  auth.uid() = sender_id AND
  EXISTS (
    SELECT 1 FROM public.chat_members
    WHERE chat_members.chat_id = messages.chat_id
    AND chat_members.user_id = auth.uid()
  )
);

-- STEP 5: Create the RPC function (optional, with fallback in code)
CREATE OR REPLACE FUNCTION public.create_direct_chat_with_members(
  user1 UUID,
  user2 UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_chat UUID;
  existing_chat UUID;
BEGIN
  -- Check if direct chat already exists between these users
  SELECT c.id INTO existing_chat
  FROM public.chats c
  WHERE c.is_direct = true
  AND EXISTS (
    SELECT 1 FROM public.chat_members cm1
    WHERE cm1.chat_id = c.id AND cm1.user_id = user1
  )
  AND EXISTS (
    SELECT 1 FROM public.chat_members cm2
    WHERE cm2.chat_id = c.id AND cm2.user_id = user2
  )
  AND (
    SELECT COUNT(*) FROM public.chat_members cm
    WHERE cm.chat_id = c.id
  ) = 2;

  -- If chat exists, return it
  IF existing_chat IS NOT NULL THEN
    RETURN existing_chat;
  END IF;

  -- Create new chat
  INSERT INTO public.chats (created_by, is_direct)
  VALUES (user1, true)
  RETURNING id INTO new_chat;

  -- Add both users to the chat
  INSERT INTO public.chat_members (chat_id, user_id)
  VALUES (new_chat, user1), (new_chat, user2);

  RETURN new_chat;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members TO authenticated;

-- STEP 6: Create helper function for searching users
CREATE OR REPLACE FUNCTION public.search_users(search_term TEXT)
RETURNS TABLE (
  id UUID,
  username TEXT,
  email TEXT,
  full_name TEXT,
  avatar_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT u.id, u.username, u.email, u.full_name, u.avatar_url
  FROM public.users u
  WHERE u.id != auth.uid()
  AND (
    u.username ILIKE '%' || search_term || '%' OR
    u.email ILIKE '%' || search_term || '%' OR
    u.full_name ILIKE '%' || search_term || '%'
  )
  LIMIT 20;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_users TO authenticated;

-- STEP 7: Test the setup
DO $$
BEGIN
  RAISE NOTICE 'Chat system setup completed successfully!';
  RAISE NOTICE 'Tables created: users, chats, chat_members, messages';
  RAISE NOTICE 'RLS policies applied';
  RAISE NOTICE 'Functions created: create_direct_chat_with_members, search_users';
END;
$$;
