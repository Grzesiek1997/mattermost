-- Function to update last_seen when user comes online
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

-- Function to update chat's last_message_at when new message is sent
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

-- Function to automatically add creator as owner when creating a chat
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

-- Function to clean up old typing indicators
CREATE OR REPLACE FUNCTION cleanup_typing_indicators()
RETURNS void AS $$
BEGIN
  DELETE FROM typing_indicators 
  WHERE updated_at < NOW() - INTERVAL '10 seconds';
END;
$$ LANGUAGE plpgsql;
