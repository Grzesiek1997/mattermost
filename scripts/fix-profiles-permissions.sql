-- Fix RLS permissions for profiles table and add missing tables
-- Based on the comprehensive Polish schema from user_read_only_context

-- Drop existing problematic policies
DROP POLICY IF EXISTS "Users can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;

-- Create simple, working RLS policies for profiles
CREATE POLICY "profiles_select_all" ON public.profiles
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "profiles_insert_own" ON public.profiles
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_own" ON public.profiles
    FOR UPDATE TO authenticated USING (auth.uid() = id);

-- Add missing tables for friend requests and friendships
CREATE TABLE IF NOT EXISTS public.friend_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    responded_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(sender_id, receiver_id)
);

CREATE TABLE IF NOT EXISTS public.friendships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user1_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    user2_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user1_id, user2_id),
    CHECK (user1_id < user2_id)
);

-- Enable RLS on new tables
ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

-- RLS policies for friend requests
CREATE POLICY "friend_requests_select_own" ON public.friend_requests
    FOR SELECT TO authenticated 
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

CREATE POLICY "friend_requests_insert_own" ON public.friend_requests
    FOR INSERT TO authenticated 
    WITH CHECK (sender_id = auth.uid());

CREATE POLICY "friend_requests_update_receiver" ON public.friend_requests
    FOR UPDATE TO authenticated 
    USING (receiver_id = auth.uid());

-- RLS policies for friendships
CREATE POLICY "friendships_select_own" ON public.friendships
    FOR SELECT TO authenticated 
    USING (user1_id = auth.uid() OR user2_id = auth.uid());

-- Add missing functions
CREATE OR REPLACE FUNCTION public.search_users(search_term TEXT)
RETURNS TABLE(
    id UUID,
    username VARCHAR,
    full_name VARCHAR,
    avatar_url TEXT,
    status VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.username,
        p.full_name,
        p.avatar_url,
        p.status
    FROM public.profiles p
    WHERE 
        p.id != auth.uid() AND
        (p.username ILIKE '%' || search_term || '%' OR 
         p.full_name ILIKE '%' || search_term || '%')
    ORDER BY p.username
    LIMIT 50;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_friend_request(receiver_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    request_id UUID;
BEGIN
    INSERT INTO public.friend_requests (sender_id, receiver_id)
    VALUES (auth.uid(), receiver_id)
    RETURNING id INTO request_id;
    
    RETURN request_id;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.search_users(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_friend_request(UUID) TO authenticated;

SELECT 'Database permissions fixed and missing tables added!' as status;
