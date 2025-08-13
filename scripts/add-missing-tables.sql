-- Add missing tables for complete functionality
-- This script adds tables that components are expecting but may not exist

-- Create notifications table
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('contact_invitation', 'contact_accepted', 'message', 'system')),
    title TEXT NOT NULL,
    message TEXT,
    data JSONB DEFAULT '{}',
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create message_reactions table
CREATE TABLE IF NOT EXISTS public.message_reactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id, emoji)
);

-- Create typing_indicators table
CREATE TABLE IF NOT EXISTS public.typing_indicators (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    is_typing BOOLEAN DEFAULT false,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- Create message_reads table
CREATE TABLE IF NOT EXISTS public.message_reads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id)
);

-- Add missing columns to messages table
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES public.messages(id);
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS file_url TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS file_name TEXT;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS file_size INTEGER;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_edited BOOLEAN DEFAULT false;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT false;

-- Add missing columns to contacts table
ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.contacts ADD COLUMN IF NOT EXISTS blocked_at TIMESTAMP WITH TIME ZONE;

-- Enable RLS on new tables
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for notifications
CREATE POLICY "Users can view their own notifications" ON public.notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "System can create notifications" ON public.notifications FOR INSERT WITH CHECK (true);
CREATE POLICY "Users can update their own notifications" ON public.notifications FOR UPDATE USING (auth.uid() = user_id);

-- Create RLS policies for message_reactions
CREATE POLICY "Users can view reactions in their chats" ON public.message_reactions FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.chat_participants WHERE chat_id IN (
        SELECT chat_id FROM public.messages WHERE id = message_reactions.message_id
    ) AND user_id = auth.uid())
);
CREATE POLICY "Users can add reactions" ON public.message_reactions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can remove their own reactions" ON public.message_reactions FOR DELETE USING (auth.uid() = user_id);

-- Create RLS policies for typing_indicators
CREATE POLICY "Users can view typing in their chats" ON public.typing_indicators FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.chat_participants WHERE chat_id = typing_indicators.chat_id AND user_id = auth.uid())
);
CREATE POLICY "Users can update their own typing status" ON public.typing_indicators FOR ALL USING (auth.uid() = user_id);

-- Create RLS policies for message_reads
CREATE POLICY "Users can view reads in their chats" ON public.message_reads FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.chat_participants WHERE chat_id IN (
        SELECT chat_id FROM public.messages WHERE id = message_reads.message_id
    ) AND user_id = auth.uid())
);
CREATE POLICY "Users can mark messages as read" ON public.message_reads FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at);
CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id ON public.message_reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_typing_indicators_chat_id ON public.typing_indicators(chat_id);
CREATE INDEX IF NOT EXISTS idx_message_reads_message_id ON public.message_reads(message_id);

-- Create trigger to send notifications for contact invitations
CREATE OR REPLACE FUNCTION public.notify_contact_invitation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    inviter_info RECORD;
BEGIN
    -- Get inviter information
    SELECT username, full_name INTO inviter_info
    FROM users WHERE id = NEW.user_id;
    
    -- Create notification for the invitee
    INSERT INTO notifications (
        user_id,
        type,
        title,
        message,
        data
    ) VALUES (
        NEW.contact_user_id,
        'contact_invitation',
        'New contact invitation',
        inviter_info.full_name || ' (@' || inviter_info.username || ') wants to connect with you',
        jsonb_build_object('invitation_id', NEW.id, 'inviter_id', NEW.user_id)
    );
    
    RETURN NEW;
END;
$$;

-- Create trigger for contact invitations
DROP TRIGGER IF EXISTS on_contact_invitation ON public.contacts;
CREATE TRIGGER on_contact_invitation
    AFTER INSERT ON public.contacts
    FOR EACH ROW
    WHEN (NEW.status = 'pending')
    EXECUTE FUNCTION public.notify_contact_invitation();

-- Grant permissions
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

SELECT 'Missing tables and functionality added successfully!' as status;
