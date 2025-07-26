-- ========================================
-- TELEGRAM CLONE - KOMPLETNA BAZA DANYCH
-- ========================================
-- Skopiuj cały ten kod i wklej do Supabase SQL Editor

-- 1. TABELA UŻYTKOWNIKÓW
CREATE TABLE IF NOT EXISTS users (
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

-- 2. TABELA CZATÓW (rozmowy grupowe, kanały, prywatne)
CREATE TABLE IF NOT EXISTS chats (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  type TEXT CHECK (type IN ('direct', 'group', 'channel')) NOT NULL,
  title TEXT,
  description TEXT,
  avatar_url TEXT,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_message_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. TABELA CZŁONKÓW CZATÓW
CREATE TABLE IF NOT EXISTS chat_members (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  role TEXT CHECK (role IN ('owner', 'admin', 'member')) DEFAULT 'member',
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  can_send_messages BOOLEAN DEFAULT true,
  can_add_members BOOLEAN DEFAULT false,
  can_delete_messages BOOLEAN DEFAULT false,
  UNIQUE(chat_id, user_id)
);

-- 4. TABELA WIADOMOŚCI
CREATE TABLE IF NOT EXISTS messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id),
  content TEXT,
  message_type TEXT CHECK (message_type IN ('text', 'image', 'file', 'voice', 'video')) DEFAULT 'text',
  file_url TEXT,
  file_name TEXT,
  file_size INTEGER,
  reply_to_id UUID REFERENCES messages(id),
  thread_id UUID REFERENCES messages(id),
  is_edited BOOLEAN DEFAULT false,
  is_deleted BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. TABELA REAKCJI NA WIADOMOŚCI
CREATE TABLE IF NOT EXISTS message_reactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(message_id, user_id, emoji)
);

-- 6. TABELA PRZECZYTANYCH WIADOMOŚCI
CREATE TABLE IF NOT EXISTS message_reads (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(message_id, user_id)
);

-- 7. TABELA KONTAKTÓW
CREATE TABLE IF NOT EXISTS contacts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  contact_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  status TEXT CHECK (status IN ('pending', 'accepted', 'blocked')) DEFAULT 'accepted',
  invited_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  accepted_at TIMESTAMP WITH TIME ZONE,
  blocked_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, contact_user_id)
);

-- 8. TABELA WSKAŹNIKÓW PISANIA
CREATE TABLE IF NOT EXISTS typing_indicators (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  is_typing BOOLEAN DEFAULT false,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(chat_id, user_id)
);

-- ========================================
-- INDEKSY DLA WYDAJNOŚCI
-- ========================================

CREATE INDEX IF NOT EXISTS idx_messages_chat_id_created_at ON messages(chat_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_reply_to_id ON messages(reply_to_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_chat_id ON chat_members(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_user_id ON chat_members(user_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id ON message_reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON contacts(status);
CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_contact_user_id ON contacts(contact_user_id);

-- ========================================
-- WŁĄCZENIE BEZPIECZEŃSTWA (RLS)
-- ========================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE typing_indicators ENABLE ROW LEVEL SECURITY;

-- ========================================
-- ZASADY BEZPIECZEŃSTWA (RLS POLICIES)
-- ========================================

-- Użytkownicy mogą czytać wszystkie profile (do wyszukiwania)
CREATE POLICY "Authenticated users can read all users" ON users
  FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Czaty - użytkownicy mogą czytać czaty, w których są członkami
CREATE POLICY "Users can read chats they are members of" ON chats
  FOR SELECT USING (
    id IN (
      SELECT chat_id FROM chat_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create chats" ON chats
  FOR INSERT WITH CHECK (created_by = auth.uid());

-- Członkowie czatów
CREATE POLICY "Users can read chat members of their chats" ON chat_members
  FOR SELECT USING (
    chat_id IN (
      SELECT chat_id FROM chat_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can add members to chats they admin" ON chat_members
  FOR INSERT WITH CHECK (
    chat_id IN (
      SELECT chat_id FROM chat_members 
      WHERE user_id = auth.uid() AND (role = 'owner' OR role = 'admin' OR can_add_members = true)
    )
  );

-- Wiadomości
CREATE POLICY "Users can read messages from their chats" ON messages
  FOR SELECT USING (
    chat_id IN (
      SELECT chat_id FROM chat_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can send messages to their chats" ON messages
  FOR INSERT WITH CHECK (
    user_id = auth.uid() AND
    chat_id IN (
      SELECT chat_id FROM chat_members 
      WHERE user_id = auth.uid() AND can_send_messages = true
    )
  );

CREATE POLICY "Users can update their own messages" ON messages
  FOR UPDATE USING (user_id = auth.uid());

-- Reakcje na wiadomości
CREATE POLICY "Users can read reactions in their chats" ON message_reactions
  FOR SELECT USING (
    message_id IN (
      SELECT m.id FROM messages m
      JOIN chat_members cm ON m.chat_id = cm.chat_id
      WHERE cm.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can add reactions to messages in their chats" ON message_reactions
  FOR INSERT WITH CHECK (
    user_id = auth.uid() AND
    message_id IN (
      SELECT m.id FROM messages m
      JOIN chat_members cm ON m.chat_id = cm.chat_id
      WHERE cm.user_id = auth.uid()
    )
  );

-- Przeczytane wiadomości
CREATE POLICY "Users can read message read status in their chats" ON message_reads
  FOR SELECT USING (
    message_id IN (
      SELECT m.id FROM messages m
      JOIN chat_members cm ON m.chat_id = cm.chat_id
      WHERE cm.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can mark messages as read" ON message_reads
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- Kontakty
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

-- Wskaźniki pisania
CREATE POLICY "Users can read typing indicators in their chats" ON typing_indicators
  FOR SELECT USING (
    chat_id IN (
      SELECT chat_id FROM chat_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update their typing status" ON typing_indicators
  FOR ALL USING (user_id = auth.uid());

-- ========================================
-- FUNKCJE I TRIGGERY
-- ========================================

-- Funkcja aktualizacji last_seen
CREATE OR REPLACE FUNCTION update_user_last_seen()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_online = true AND OLD.is_online = false THEN
    NEW.last_seen = NOW();
  END IF;
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_user_last_seen
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION update_user_last_seen();

-- Funkcja aktualizacji ostatniej wiadomości w czacie
CREATE OR REPLACE FUNCTION update_chat_last_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE chats 
  SET last_message_at = NEW.created_at, updated_at = NOW()
  WHERE id = NEW.chat_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_chat_last_message
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_chat_last_message();

-- Funkcja automatycznego dodawania twórcy jako właściciela czatu
CREATE OR REPLACE FUNCTION add_chat_creator_as_owner()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO chat_members (chat_id, user_id, role, can_send_messages, can_add_members, can_delete_messages)
  VALUES (NEW.id, NEW.created_by, 'owner', true, true, true);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_add_chat_creator_as_owner
  AFTER INSERT ON chats
  FOR EACH ROW
  EXECUTE FUNCTION add_chat_creator_as_owner();

-- Funkcja wyszukiwania użytkowników
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Nadanie uprawnień
GRANT EXECUTE ON FUNCTION get_searchable_users TO authenticated;

-- ========================================
-- PRZYKŁADOWI UŻYTKOWNICY DO TESTÓW
-- ========================================

INSERT INTO users (id, email, username, full_name, bio, is_online, avatar_url) VALUES
  ('11111111-1111-1111-1111-111111111111', 'john.doe@test.com', 'johndoe', 'John Doe', 'Software Developer at Tech Corp', true, '/placeholder.svg?height=40&width=40&text=JD'),
  ('22222222-2222-2222-2222-222222222222', 'jane.smith@test.com', 'janesmith', 'Jane Smith', 'UI/UX Designer | Creative Professional', false, '/placeholder.svg?height=40&width=40&text=JS'),
  ('33333333-3333-3333-3333-333333333333', 'mike.wilson@test.com', 'mikewilson', 'Mike Wilson', 'Product Manager | Tech Enthusiast', true, '/placeholder.svg?height=40&width=40&text=MW'),
  ('44444444-4444-4444-4444-444444444444', 'sarah.johnson@test.com', 'sarahj', 'Sarah Johnson', 'Marketing Specialist | Content Creator', false, '/placeholder.svg?height=40&width=40&text=SJ'),
  ('55555555-5555-5555-5555-555555555555', 'alex.brown@test.com', 'alexbrown', 'Alex Brown', 'Data Scientist | AI/ML Engineer', true, '/placeholder.svg?height=40&width=40&text=AB')
ON CONFLICT (id) DO UPDATE SET
  email = EXCLUDED.email,
  username = EXCLUDED.username,
  full_name = EXCLUDED.full_name,
  bio = EXCLUDED.bio,
  is_online = EXCLUDED.is_online,
  avatar_url = EXCLUDED.avatar_url;

-- ========================================
-- GOTOWE! 🎉
-- ========================================
-- Twoja baza danych Telegram Clone jest gotowa!
-- Możesz teraz używać aplikacji z pełną funkcjonalnością.
