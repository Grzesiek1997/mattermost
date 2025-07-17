-- RLS Policies for Security

-- Users can read their own profile and profiles of users they have chats with
CREATE POLICY "Users can read own profile" ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

-- Chat access policies
CREATE POLICY "Users can read chats they are members of" ON chats
  FOR SELECT USING (
    id IN (
      SELECT chat_id FROM chat_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create chats" ON chats
  FOR INSERT WITH CHECK (created_by = auth.uid());

-- Chat members policies
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

-- Messages policies
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

-- Message reactions policies
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

-- Message reads policies
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

-- Contacts policies
CREATE POLICY "Users can read their contacts" ON contacts
  FOR SELECT USING (user_id = auth.uid() OR contact_user_id = auth.uid());

CREATE POLICY "Users can manage their contacts" ON contacts
  FOR ALL USING (user_id = auth.uid());

-- Typing indicators policies
CREATE POLICY "Users can read typing indicators in their chats" ON typing_indicators
  FOR SELECT USING (
    chat_id IN (
      SELECT chat_id FROM chat_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update their typing status" ON typing_indicators
  FOR ALL USING (user_id = auth.uid());
