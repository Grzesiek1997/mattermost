-- Fix admin functions and authentication system
-- This script ensures all admin functions work properly with the AuthService

-- First, ensure admin_users table exists with correct structure
CREATE TABLE IF NOT EXISTS public.admin_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
    role TEXT DEFAULT 'admin' CHECK (role IN ('admin', 'super_admin')),
    permissions JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES public.users(id)
);

-- Enable RLS on admin_users
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- Create RLS policy for admin_users
DROP POLICY IF EXISTS "Only admins can view admin users" ON public.admin_users;
CREATE POLICY "Only admins can view admin users" ON public.admin_users FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "Super admins can manage admin users" ON public.admin_users;
CREATE POLICY "Super admins can manage admin users" ON public.admin_users FOR ALL USING (
    EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid() AND role = 'super_admin')
);

-- Create or replace the is_admin function
CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    check_user_id UUID;
BEGIN
    -- Use provided user_id or current auth user
    check_user_id := COALESCE(user_uuid, auth.uid());
    
    -- Return false if no user to check
    IF check_user_id IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- Check if user exists in admin_users table
    RETURN EXISTS (
        SELECT 1 FROM admin_users 
        WHERE user_id = check_user_id
    );
END;
$$;

-- Create or replace the get_admin_role function
CREATE OR REPLACE FUNCTION public.get_admin_role(user_uuid UUID DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    check_user_id UUID;
    admin_role TEXT;
BEGIN
    -- Use provided user_id or current auth user
    check_user_id := COALESCE(user_uuid, auth.uid());
    
    -- Return 'user' if no user to check
    IF check_user_id IS NULL THEN
        RETURN 'user';
    END IF;
    
    -- Get admin role
    SELECT role INTO admin_role
    FROM admin_users 
    WHERE user_id = check_user_id;
    
    -- Return role or 'user' if not admin
    RETURN COALESCE(admin_role, 'user');
END;
$$;

-- Create or replace the create_first_super_admin function
CREATE OR REPLACE FUNCTION public.create_first_super_admin()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    admin_count INTEGER;
BEGIN
    -- Get current authenticated user
    current_user_id := auth.uid();
    
    IF current_user_id IS NULL THEN
        RETURN 'Error: Not authenticated';
    END IF;
    
    -- Check if any admins already exist
    SELECT COUNT(*) INTO admin_count FROM admin_users;
    
    IF admin_count > 0 THEN
        RETURN 'Error: Admin users already exist';
    END IF;
    
    -- Create first super admin
    INSERT INTO admin_users (user_id, role, created_by)
    VALUES (current_user_id, 'super_admin', current_user_id);
    
    RETURN 'Success: First super admin created';
END;
$$;

-- Create or replace the promote_user_to_admin function
CREATE OR REPLACE FUNCTION public.promote_user_to_admin(target_email TEXT, admin_role TEXT DEFAULT 'admin')
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    target_user_id UUID;
    current_role TEXT;
BEGIN
    -- Get current authenticated user
    current_user_id := auth.uid();
    
    IF current_user_id IS NULL THEN
        RETURN 'Error: Not authenticated';
    END IF;
    
    -- Check if current user is super admin
    SELECT role INTO current_role FROM admin_users WHERE user_id = current_user_id;
    
    IF current_role != 'super_admin' THEN
        RETURN 'Error: Only super admins can promote users';
    END IF;
    
    -- Find target user by email
    SELECT id INTO target_user_id FROM users WHERE email = target_email;
    
    IF target_user_id IS NULL THEN
        RETURN 'Error: User not found with email: ' || target_email;
    END IF;
    
    -- Validate admin role
    IF admin_role NOT IN ('admin', 'super_admin') THEN
        RETURN 'Error: Invalid role. Must be admin or super_admin';
    END IF;
    
    -- Insert or update admin user
    INSERT INTO admin_users (user_id, role, created_by)
    VALUES (target_user_id, admin_role, current_user_id)
    ON CONFLICT (user_id) 
    DO UPDATE SET 
        role = admin_role,
        created_by = current_user_id;
    
    RETURN 'Success: User promoted to ' || admin_role;
END;
$$;

-- Create test_user_creation function for debugging
CREATE OR REPLACE FUNCTION public.test_user_creation(test_email TEXT, test_username TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    test_result TEXT;
BEGIN
    -- Get current authenticated user
    current_user_id := auth.uid();
    
    IF current_user_id IS NULL THEN
        RETURN 'Error: Not authenticated for RLS test';
    END IF;
    
    -- Test if we can read from users table
    BEGIN
        PERFORM COUNT(*) FROM users WHERE id = current_user_id;
        test_result := 'Success: Can read users table';
    EXCEPTION WHEN OTHERS THEN
        test_result := 'Error: Cannot read users table - ' || SQLERRM;
    END;
    
    RETURN test_result;
END;
$$;

-- Grant permissions to all functions
GRANT EXECUTE ON FUNCTION public.is_admin TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_admin_role TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.create_first_super_admin TO authenticated;
GRANT EXECUTE ON FUNCTION public.promote_user_to_admin TO authenticated;
GRANT EXECUTE ON FUNCTION public.test_user_creation TO authenticated;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_admin_users_user_id ON public.admin_users(user_id);
CREATE INDEX IF NOT EXISTS idx_admin_users_role ON public.admin_users(role);

-- Test the functions
SELECT 'Admin functions setup complete!' as status;

-- Show current admin count
SELECT 'Current admin count: ' || COUNT(*) as admin_info FROM public.admin_users;

-- Test is_admin function (should return false for non-admin users)
SELECT 'is_admin test: ' || COALESCE(public.is_admin()::TEXT, 'NULL') as test_result;
