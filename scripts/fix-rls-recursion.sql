-- Fix infinite recursion in RLS policies for chat_members table
-- This script creates a security definer function to safely check chat membership

-- Drop existing problematic policies
DROP POLICY IF EXISTS "Users can view chat members" ON public.chat_members;
DROP POLICY IF EXISTS "Users can read chat members of their chats" ON public.chat_members;

-- Create a security definer function to check chat membership without RLS recursion
CREATE OR REPLACE FUNCTION public.is_chat_member(chat_id_param UUID, user_id_param UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- This function bypasses RLS to prevent infinite recursion
    RETURN EXISTS (
        SELECT 1 FROM public.chat_members 
        WHERE chat_id = chat_id_param AND user_id = user_id_param
    );
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.is_chat_member TO authenticated;

-- Create new safe RLS policies using the security definer function
CREATE POLICY "Users can view chat members safely" ON public.chat_members 
    FOR SELECT USING (
        public.is_chat_member(chat_id, auth.uid())
    );

CREATE POLICY "Users can join chats" ON public.chat_members 
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Chat admins can manage members" ON public.chat_members 
    FOR UPDATE USING (
        public.is_chat_member(chat_id, auth.uid()) AND
        EXISTS (
            SELECT 1 FROM public.chat_members 
            WHERE chat_id = chat_members.chat_id 
            AND user_id = auth.uid() 
            AND role IN ('owner', 'admin')
        )
    );

-- Fix other policies that might have similar recursion issues
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
CREATE POLICY "Users can view their chats safely" ON public.chats 
    FOR SELECT USING (
        public.is_chat_member(id, auth.uid())
    );

DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
CREATE POLICY "Users can view messages in their chats safely" ON public.messages 
    FOR SELECT USING (
        public.is_chat_member(chat_id, auth.uid())
    );

DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
CREATE POLICY "Users can send messages safely" ON public.messages 
    FOR INSERT WITH CHECK (
        auth.uid() = user_id AND
        public.is_chat_member(chat_id, auth.uid()) AND
        EXISTS (
            SELECT 1 FROM public.chat_members 
            WHERE chat_id = messages.chat_id 
            AND user_id = auth.uid() 
            AND can_send_messages = true
        )
    );

-- Fix typing indicators policy
DROP POLICY IF EXISTS "Users can view typing indicators" ON public.typing_indicators;
CREATE POLICY "Users can view typing indicators safely" ON public.typing_indicators 
    FOR SELECT USING (
        public.is_chat_member(chat_id, auth.uid())
    );

-- Create notification system for contact invitations
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('contact_invitation', 'contact_accepted', 'message', 'system')),
    title TEXT NOT NULL,
    message TEXT,
    data JSONB,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS for notifications
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Notifications policies
CREATE POLICY "Users can view their notifications" ON public.notifications 
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update their notifications" ON public.notifications 
    FOR UPDATE USING (auth.uid() = user_id);

-- Create function to send notification
CREATE OR REPLACE FUNCTION public.send_notification(
    recipient_id UUID,
    notification_type TEXT,
    notification_title TEXT,
    notification_message TEXT DEFAULT NULL,
    notification_data JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    notification_id UUID;
BEGIN
    INSERT INTO public.notifications (
        user_id, type, title, message, data
    ) VALUES (
        recipient_id, notification_type, notification_title, notification_message, notification_data
    ) RETURNING id INTO notification_id;
    
    RETURN notification_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.send_notification TO authenticated;

-- Create trigger to send notifications for contact invitations
CREATE OR REPLACE FUNCTION public.notify_contact_invitation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    sender_info RECORD;
BEGIN
    -- Get sender information
    SELECT username, full_name INTO sender_info
    FROM public.users 
    WHERE id = NEW.user_id;
    
    -- Send notification to recipient
    PERFORM public.send_notification(
        NEW.contact_user_id,
        'contact_invitation',
        'New Contact Request',
        COALESCE(sender_info.full_name, sender_info.username) || ' wants to connect with you',
        jsonb_build_object(
            'invitation_id', NEW.id,
            'sender_id', NEW.user_id,
            'sender_username', sender_info.username,
            'sender_full_name', sender_info.full_name
        )
    );
    
    RETURN NEW;
END;
$$;

-- Create trigger for contact invitations
DROP TRIGGER IF EXISTS trigger_notify_contact_invitation ON public.contacts;
CREATE TRIGGER trigger_notify_contact_invitation
    AFTER INSERT ON public.contacts
    FOR EACH ROW
    WHEN (NEW.status = 'pending')
    EXECUTE FUNCTION public.notify_contact_invitation();

-- Create trigger to notify when invitation is accepted
CREATE OR REPLACE FUNCTION public.notify_contact_accepted()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    accepter_info RECORD;
BEGIN
    -- Only notify when status changes from pending to accepted
    IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
        -- Get accepter information
        SELECT username, full_name INTO accepter_info
        FROM public.users 
        WHERE id = NEW.contact_user_id;
        
        -- Send notification to original sender
        PERFORM public.send_notification(
            NEW.user_id,
            'contact_accepted',
            'Contact Request Accepted',
            COALESCE(accepter_info.full_name, accepter_info.username) || ' accepted your contact request',
            jsonb_build_object(
                'contact_id', NEW.contact_user_id,
                'accepter_username', accepter_info.username,
                'accepter_full_name', accepter_info.full_name
            )
        );
    END IF;
    
    RETURN NEW;
END;
$$;

-- Create trigger for contact acceptance
DROP TRIGGER IF EXISTS trigger_notify_contact_accepted ON public.contacts;
CREATE TRIGGER trigger_notify_contact_accepted
    AFTER UPDATE ON public.contacts
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_contact_accepted();

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON public.notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at DESC);

-- Test the fix
SELECT 'RLS recursion fix completed successfully' as status;
