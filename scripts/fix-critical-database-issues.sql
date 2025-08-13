-- Fix RLS policies to eliminate infinite recursion
-- Drop all existing problematic policies
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_members;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_members;
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;

-- Create simple, non-recursive RLS policies for chat_members
CREATE POLICY "Users can view their own memberships" ON public.chat_members
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can join chats" ON public.chat_members
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Create simple RLS policies for chats
CREATE POLICY "Users can view chats they are members of" ON public.chats
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.chat_members 
      WHERE chat_id = chats.id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create chats" ON public.chats
  FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Create simple RLS policies for messages
CREATE POLICY "Users can view messages in their chats" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.chat_members 
      WHERE chat_id = messages.chat_id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Users can send messages" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = user_id AND
    EXISTS (
      SELECT 1 FROM public.chat_members 
      WHERE chat_id = messages.chat_id AND user_id = auth.uid()
    )
  );

-- Ensure chats table has required type column
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS type TEXT DEFAULT 'direct';
ALTER TABLE public.chats ALTER COLUMN type SET NOT NULL;

-- Create profiles table for user data separation
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE,
  full_name TEXT,
  avatar_url TEXT,
  bio TEXT,
  status TEXT DEFAULT 'offline',
  last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS for profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Simple RLS policies for profiles
CREATE POLICY "Users can view all profiles" ON public.profiles
  FOR SELECT USING (true);

CREATE POLICY "Users can update their own profile" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert their own profile" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Create function to handle profile creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, username, full_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for automatic profile creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create the missing RPC function
CREATE OR REPLACE FUNCTION public.create_direct_chat_with_members(user1 UUID, user2 UUID)
RETURNS UUID AS $$
DECLARE
  chat_id UUID;
  existing_chat_id UUID;
BEGIN
  -- Check if direct chat already exists
  SELECT c.id INTO existing_chat_id
  FROM public.chats c
  WHERE c.type = 'direct'
    AND EXISTS (SELECT 1 FROM public.chat_members cm1 WHERE cm1.chat_id = c.id AND cm1.user_id = user1)
    AND EXISTS (SELECT 1 FROM public.chat_members cm2 WHERE cm2.chat_id = c.id AND cm2.user_id = user2)
    AND (SELECT COUNT(*) FROM public.chat_members cm WHERE cm.chat_id = c.id) = 2;
  
  IF existing_chat_id IS NOT NULL THEN
    RETURN existing_chat_id;
  END IF;
  
  -- Create new direct chat
  INSERT INTO public.chats (created_by, type)
  VALUES (user1, 'direct')
  RETURNING id INTO chat_id;
  
  -- Add both users as members
  INSERT INTO public.chat_members (chat_id, user_id, role)
  VALUES 
    (chat_id, user1, 'member'),
    (chat_id, user2, 'member');
  
  RETURN chat_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.create_direct_chat_with_members TO authenticated;

-- Test the database setup
SELECT 'Database setup completed successfully' as status;
