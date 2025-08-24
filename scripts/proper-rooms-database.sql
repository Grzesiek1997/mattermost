-- Complete Supabase Chat Database Schema
-- Based on Gemini suggestions and Supabase best practices

-- First, drop existing objects to avoid conflicts
DROP POLICY IF EXISTS "Users can view all profiles" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "Users can view rooms they participate in" ON rooms;
DROP POLICY IF EXISTS "Users can view participants in same room" ON room_participants;
DROP POLICY IF EXISTS "Users can send messages in their rooms" ON messages;
DROP POLICY IF EXISTS "Users can read messages in their rooms" ON messages;
DROP POLICY IF EXISTS "Users can manage own receipts" ON message_receipts;
DROP POLICY IF EXISTS "Senders can view message receipts" ON message_receipts;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

DROP TABLE IF EXISTS message_receipts CASCADE;
DROP TABLE IF EXISTS messages CASCADE;
DROP TABLE IF EXISTS room_participants CASCADE;
DROP TABLE IF EXISTS rooms CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

DROP TYPE IF EXISTS message_status;
DROP TYPE IF EXISTS participant_role;
DROP TYPE IF EXISTS room_type;

-- Create custom types
CREATE TYPE room_type AS ENUM ('private', 'group');
CREATE TYPE participant_role AS ENUM ('member', 'admin');
CREATE TYPE message_status AS ENUM ('sent', 'delivered', 'read');

-- 1. Profiles table (extends auth.users)
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  bio TEXT,
  phone TEXT,
  status TEXT DEFAULT 'online',
  public_key TEXT, -- For future E2EE implementation
  last_seen TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT username_length CHECK (char_length(username) >= 3)
);

-- Enable RLS on profiles
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies for profiles
CREATE POLICY "Users can view all profiles" ON profiles
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- 2. Rooms table (conversations)
CREATE TABLE rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type room_type NOT NULL DEFAULT 'private',
  name TEXT, -- Name for group chats
  description TEXT,
  avatar_url TEXT,
  creator_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on rooms
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;

-- RLS Policies for rooms
CREATE POLICY "Users can view rooms they participate in" ON rooms
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM room_participants 
      WHERE room_id = rooms.id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create rooms" ON rooms
  FOR INSERT WITH CHECK (auth.uid() = creator_id);

-- 3. Room participants table
CREATE TABLE room_participants (
  room_id UUID REFERENCES rooms(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  role participant_role DEFAULT 'member',
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  left_at TIMESTAMPTZ,

  PRIMARY KEY (room_id, user_id)
);

-- Enable RLS on room_participants
ALTER TABLE room_participants ENABLE ROW LEVEL SECURITY;

-- RLS Policies for room_participants
CREATE POLICY "Users can view participants in same room" ON room_participants
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM room_participants rp2 
      WHERE rp2.room_id = room_participants.room_id AND rp2.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can join rooms" ON room_participants
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 4. Messages table
CREATE TABLE messages (
  id BIGSERIAL PRIMARY KEY,
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  message_type TEXT DEFAULT 'text', -- text, image, file, etc.
  file_url TEXT,
  reply_to_id BIGINT REFERENCES messages(id),
  edited_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on messages
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- RLS Policies for messages
CREATE POLICY "Users can send messages in their rooms" ON messages
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM room_participants 
      WHERE room_id = messages.room_id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Users can read messages in their rooms" ON messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM room_participants 
      WHERE room_id = messages.room_id AND user_id = auth.uid()
    )
  );

-- 5. Message receipts table (read status)
CREATE TABLE message_receipts (
  message_id BIGINT REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  status message_status NOT NULL DEFAULT 'delivered',
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  PRIMARY KEY (message_id, user_id)
);

-- Enable RLS on message_receipts
ALTER TABLE message_receipts ENABLE ROW LEVEL SECURITY;

-- RLS Policies for message_receipts
CREATE POLICY "Users can manage own receipts" ON message_receipts
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Senders can view message receipts" ON message_receipts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM messages 
      WHERE id = message_receipts.message_id AND sender_id = auth.uid()
    )
  );

-- 6. Friendships table
CREATE TABLE friendships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  friend_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'pending', -- pending, accepted, blocked
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, friend_id),
  CHECK (user_id != friend_id)
);

-- Enable RLS on friendships
ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;

-- RLS Policies for friendships
CREATE POLICY "Users can view own friendships" ON friendships
  FOR SELECT USING (auth.uid() = user_id OR auth.uid() = friend_id);

CREATE POLICY "Users can create friendships" ON friendships
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own friendships" ON friendships
  FOR UPDATE USING (auth.uid() = user_id OR auth.uid() = friend_id);

-- Create indexes for performance
CREATE INDEX idx_profiles_username ON profiles(username);
CREATE INDEX idx_room_participants_room_id ON room_participants(room_id);
CREATE INDEX idx_room_participants_user_id ON room_participants(user_id);
CREATE INDEX idx_messages_room_id ON messages(room_id);
CREATE INDEX idx_messages_sender_id ON messages(sender_id);
CREATE INDEX idx_messages_created_at ON messages(created_at DESC);
CREATE INDEX idx_message_receipts_message_id ON message_receipts(message_id);
CREATE INDEX idx_friendships_user_id ON friendships(user_id);
CREATE INDEX idx_friendships_friend_id ON friendships(friend_id);

-- Function to automatically create profile after user registration
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, username, full_name)
  VALUES (
    new.id, 
    COALESCE(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8)),
    COALESCE(new.raw_user_meta_data->>'full_name', new.email)
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function after user registration
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Utility functions
CREATE OR REPLACE FUNCTION get_user_rooms(p_user_id UUID)
RETURNS TABLE (
  room_id UUID,
  room_name TEXT,
  room_type room_type,
  last_message TEXT,
  last_message_at TIMESTAMPTZ,
  unread_count BIGINT
) 
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    r.id,
    CASE 
      WHEN r.type = 'private' THEN (
        SELECT p.full_name 
        FROM room_participants rp2 
        JOIN profiles p ON p.id = rp2.user_id 
        WHERE rp2.room_id = r.id AND rp2.user_id != p_user_id 
        LIMIT 1
      )
      ELSE r.name
    END,
    r.type,
    (SELECT m.content FROM messages m WHERE m.room_id = r.id ORDER BY m.created_at DESC LIMIT 1),
    (SELECT m.created_at FROM messages m WHERE m.room_id = r.id ORDER BY m.created_at DESC LIMIT 1),
    (SELECT COUNT(*) FROM messages m WHERE m.room_id = r.id AND m.sender_id != p_user_id)::BIGINT
  FROM rooms r
  JOIN room_participants rp ON rp.room_id = r.id
  WHERE rp.user_id = p_user_id
  ORDER BY (SELECT m.created_at FROM messages m WHERE m.room_id = r.id ORDER BY m.created_at DESC LIMIT 1) DESC NULLS LAST;
END;
$$;

CREATE OR REPLACE FUNCTION search_users(search_term TEXT)
RETURNS TABLE (
  id UUID,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.username, p.full_name, p.avatar_url
  FROM profiles p
  WHERE p.username ILIKE '%' || search_term || '%' 
     OR p.full_name ILIKE '%' || search_term || '%'
  LIMIT 20;
END;
$$;

CREATE OR REPLACE FUNCTION create_direct_room(p_user_id UUID, p_friend_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  room_id UUID;
BEGIN
  -- Check if room already exists
  SELECT r.id INTO room_id
  FROM rooms r
  JOIN room_participants rp1 ON rp1.room_id = r.id AND rp1.user_id = p_user_id
  JOIN room_participants rp2 ON rp2.room_id = r.id AND rp2.user_id = p_friend_id
  WHERE r.type = 'private'
  LIMIT 1;
  
  IF room_id IS NULL THEN
    -- Create new room
    INSERT INTO rooms (type, creator_id) VALUES ('private', p_user_id) RETURNING id INTO room_id;
    
    -- Add participants
    INSERT INTO room_participants (room_id, user_id) VALUES (room_id, p_user_id);
    INSERT INTO room_participants (room_id, user_id) VALUES (room_id, p_friend_id);
  END IF;
  
  RETURN room_id;
END;
$$;

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Test the setup
SELECT 'Database setup complete - rooms schema ready!' as status;
