-- ADD MISSING DATABASE FUNCTIONS
-- This script adds the functions that are missing from the database

-- Function to check if user is admin
CREATE OR REPLACE FUNCTION public.is_admin(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin boolean := false;
BEGIN
    -- Simple admin check - you can customize this logic
    -- For now, just return false since we don't have user_roles table
    -- You can modify this to check a specific admin table or field
    SELECT EXISTS(
        SELECT 1 
        FROM profiles 
        WHERE id = p_user_id 
        AND username IN ('admin', 'super_admin')
    ) INTO v_is_admin;
    
    RETURN v_is_admin;
END;
$$;

-- Function to get user conversations (bypasses RLS)
CREATE OR REPLACE FUNCTION public.get_user_conversations(p_user_id uuid)
RETURNS TABLE(
    id uuid,
    name text,
    type text,
    avatar_url text,
    created_at timestamptz,
    last_message text,
    last_message_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.name,
        c.type,
        c.avatar_url,
        c.created_at,
        m.content as last_message,
        m.created_at as last_message_at
    FROM conversations c
    INNER JOIN conversation_participants cp ON c.id = cp.conversation_id
    LEFT JOIN LATERAL (
        SELECT content, created_at
        FROM messages
        WHERE conversation_id = c.id
        ORDER BY created_at DESC
        LIMIT 1
    ) m ON true
    WHERE cp.user_id = p_user_id
    ORDER BY COALESCE(m.created_at, c.created_at) DESC;
END;
$$;

-- Function to search users (bypasses RLS)
CREATE OR REPLACE FUNCTION public.search_users(search_term text)
RETURNS TABLE(
    id uuid,
    username text,
    full_name text,
    avatar_url text
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
        p.avatar_url
    FROM profiles p
    WHERE p.username ILIKE '%' || search_term || '%' 
       OR p.full_name ILIKE '%' || search_term || '%'
    LIMIT 20;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.is_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_conversations(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_users(text) TO authenticated;

SELECT 'Missing functions added successfully!' as status;
