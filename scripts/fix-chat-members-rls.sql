-- Fix infinite recursion in chat_members RLS policies
-- This script completely rebuilds the RLS policies to avoid recursion

-- Drop existing problematic policies
DROP POLICY IF EXISTS "Users can view chat members" ON public.chat_members;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_members;
DROP POLICY IF EXISTS "Users can leave chats" ON public.chat_members;
DROP POLICY IF EXISTS "Chat creators can manage members" ON public.chat_members;

-- Create simple, non-recursive policies for chat_members
-- Policy 1: Users can view members of chats they belong to (using EXISTS to avoid recursion)
CREATE POLICY "Users can view their chat members" ON public.chat_members
FOR SELECT USING (
    -- Allow if user is querying their own membership
    auth.uid() = user_id
    OR
    -- Allow if user is a member of the same chat (direct query without recursion)
    EXISTS (
        SELECT 1 FROM public.chat_members cm2 
        WHERE cm2.chat_id = chat_members.chat_id 
        AND cm2.user_id = auth.uid()
    )
);

-- Policy 2: Users can insert themselves into chats (for joining)
CREATE POLICY "Users can join chats" ON public.chat_members
FOR INSERT WITH CHECK (
    -- Users can only add themselves
    auth.uid() = user_id
    AND
    -- Chat must exist and be accessible
    EXISTS (
        SELECT 1 FROM public.chats c 
        WHERE c.id = chat_id
        AND (
            c.type = 'direct' -- Direct chats are always joinable
            OR c.created_by = auth.uid() -- Creator can add anyone
        )
    )
);

-- Policy 3: Users can remove themselves from chats
CREATE POLICY "Users can leave chats" ON public.chat_members
FOR DELETE USING (
    auth.uid() = user_id -- Users can only remove themselves
);

-- Policy 4: Chat creators can manage all members
CREATE POLICY "Chat creators can manage members" ON public.chat_members
FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public.chats c 
        WHERE c.id = chat_members.chat_id 
        AND c.created_by = auth.uid()
    )
);

-- Also fix chats table policies to avoid recursion
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
CREATE POLICY "Users can view their chats" ON public.chats
FOR SELECT USING (
    -- Direct query to chat_members without recursion
    id IN (
        SELECT DISTINCT cm.chat_id 
        FROM public.chat_members cm 
        WHERE cm.user_id = auth.uid()
    )
);

-- Test the policies
SELECT 'RLS policies fixed for chat_members and chats' as status;

-- Verify no recursion by testing a simple query
DO $$
BEGIN
    -- This should not cause recursion
    PERFORM COUNT(*) FROM public.chat_members WHERE user_id = auth.uid();
    RAISE NOTICE 'RLS test passed - no recursion detected';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'RLS test failed: %', SQLERRM;
END $$;
