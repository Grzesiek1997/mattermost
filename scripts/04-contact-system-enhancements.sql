-- Enhance contacts table with invitation system
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS invited_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS blocked_at TIMESTAMP WITH TIME ZONE;

-- Create contact invitations view for easier querying
CREATE OR REPLACE VIEW contact_invitations AS
SELECT 
  c.*,
  inviter.username as inviter_username,
  inviter.full_name as inviter_full_name,
  inviter.avatar_url as inviter_avatar_url,
  invitee.username as invitee_username,
  invitee.full_name as invitee_full_name,
  invitee.avatar_url as invitee_avatar_url
FROM contacts c
LEFT JOIN users inviter ON c.user_id = inviter.id
LEFT JOIN users invitee ON c.contact_user_id = invitee.id;

-- Function to create mutual contact relationship
CREATE OR REPLACE FUNCTION create_mutual_contact(
  user1_id UUID,
  user2_id UUID
) RETURNS void AS $$
BEGIN
  -- Insert contact relationship from user1 to user2
  INSERT INTO contacts (user_id, contact_user_id, status, accepted_at)
  VALUES (user1_id, user2_id, 'accepted', NOW())
  ON CONFLICT (user_id, contact_user_id) 
  DO UPDATE SET status = 'accepted', accepted_at = NOW();
  
  -- Insert contact relationship from user2 to user1
  INSERT INTO contacts (user_id, contact_user_id, status, accepted_at)
  VALUES (user2_id, user1_id, 'accepted', NOW())
  ON CONFLICT (user_id, contact_user_id) 
  DO UPDATE SET status = 'accepted', accepted_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- Function to send contact invitation
CREATE OR REPLACE FUNCTION send_contact_invitation(
  sender_id UUID,
  receiver_id UUID
) RETURNS void AS $$
BEGIN
  -- Insert invitation from sender to receiver
  INSERT INTO contacts (user_id, contact_user_id, status, invited_at)
  VALUES (sender_id, receiver_id, 'pending', NOW())
  ON CONFLICT (user_id, contact_user_id) 
  DO UPDATE SET status = 'pending', invited_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_contacts_status ON contacts(status);
CREATE INDEX IF NOT EXISTS idx_contacts_invited_at ON contacts(invited_at);
CREATE INDEX IF NOT EXISTS idx_contacts_accepted_at ON contacts(accepted_at);
CREATE INDEX IF NOT EXISTS idx_users_search ON users(username, full_name, email);
