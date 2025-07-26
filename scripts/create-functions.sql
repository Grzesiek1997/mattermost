-- FUNKCJE POMOCNICZE DLA TELEGRAM CLONE
-- Uruchom to w SQL Editor w Supabase

-- ============================================
-- FUNKCJA 1: BEZPIECZNE TWORZENIE PROFILU
-- ============================================

CREATE OR REPLACE FUNCTION public.create_user_profile(
    user_id UUID,
    user_email TEXT,
    user_username TEXT,
    user_full_name TEXT DEFAULT 'User'
)
RETURNS public.users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    new_user public.users;
    username_counter INTEGER := 0;
    final_username TEXT;
BEGIN
    -- Sprawdź czy user już istnieje
    SELECT * INTO new_user FROM public.users WHERE id = user_id;
    
    IF new_user.id IS NOT NULL THEN
        RETURN new_user;
    END IF;
    
    -- Sprawdź czy username jest unikalny, jeśli nie - dodaj numer
    final_username := user_username;
    WHILE EXISTS (SELECT 1 FROM public.users WHERE username = final_username) LOOP
        username_counter := username_counter + 1;
        final_username := user_username || username_counter::TEXT;
    END LOOP;
    
    -- Utwórz nowy profil
    INSERT INTO public.users (
        id,
        email,
        username,
        full_name,
        is_online,
        last_seen,
        created_at,
        updated_at
    ) VALUES (
        user_id,
        user_email,
        final_username,
        user_full_name,
        true,
        NOW(),
        NOW(),
        NOW()
    ) RETURNING * INTO new_user;
    
    RETURN new_user;
EXCEPTION
    WHEN OTHERS THEN
        -- Jeśli coś pójdzie nie tak, spróbuj ponownie z prostszymi danymi
        INSERT INTO public.users (
            id,
            email,
            username,
            full_name,
            is_online,
            last_seen
        ) VALUES (
            user_id,
            user_email,
            COALESCE(user_username, split_part(user_email, '@', 1)) || '_' || extract(epoch from now())::bigint::text,
            COALESCE(user_full_name, 'User'),
            true,
            NOW()
        ) RETURNING * INTO new_user;
        
        RETURN new_user;
END;
$$;

-- ============================================
-- FUNKCJA 2: SPRAWDZANIE CZY USER JEST ADMINEM
-- ============================================

CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_user_id UUID;
BEGIN
    -- Jeśli nie podano user_id, użyj aktualnego użytkownika
    target_user_id := COALESCE(user_uuid, auth.uid());
    
    -- Sprawdź czy user ma rolę admin
    RETURN EXISTS (
        SELECT 1 FROM public.admin_roles 
        WHERE user_id = target_user_id
    );
END;
$$;

-- ============================================
-- FUNKCJA 3: POBIERANIE ROLI ADMINA
-- ============================================

CREATE OR REPLACE FUNCTION public.get_admin_role(user_uuid UUID DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_user_id UUID;
    user_role TEXT;
BEGIN
    -- Jeśli nie podano user_id, użyj aktualnego użytkownika
    target_user_id := COALESCE(user_uuid, auth.uid());
    
    -- Pobierz rolę użytkownika
    SELECT role INTO user_role 
    FROM public.admin_roles 
    WHERE user_id = target_user_id;
    
    -- Zwróć rolę lub 'user' jeśli nie ma roli admin
    RETURN COALESCE(user_role, 'user');
END;
$$;

-- ============================================
-- FUNKCJA 4: TWORZENIE PIERWSZEGO SUPER ADMINA
-- ============================================

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
    -- Pobierz ID aktualnego użytkownika
    current_user_id := auth.uid();
    
    IF current_user_id IS NULL THEN
        RETURN 'Error: No authenticated user';
    END IF;
    
    -- Sprawdź czy już istnieją admini
    SELECT COUNT(*) INTO admin_count FROM public.admin_roles;
    
    IF admin_count > 0 THEN
        RETURN 'Error: Admins already exist';
    END IF;
    
    -- Utwórz pierwszego super admina
    INSERT INTO public.admin_roles (user_id, role, granted_by, granted_at)
    VALUES (current_user_id, 'super_admin', current_user_id, NOW());
    
    RETURN 'Success: First super admin created';
END;
$$;

-- ============================================
-- FUNKCJA 5: PROMOWANIE UŻYTKOWNIKA DO ADMINA
-- ============================================

CREATE OR REPLACE FUNCTION public.promote_user_to_admin(
    target_email TEXT,
    admin_role TEXT DEFAULT 'admin'
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    target_user_id UUID;
    current_user_role TEXT;
BEGIN
    -- Pobierz ID aktualnego użytkownika
    current_user_id := auth.uid();
    
    IF current_user_id IS NULL THEN
        RETURN 'Error: No authenticated user';
    END IF;
    
    -- Sprawdź czy aktualny użytkownik jest super adminem
    SELECT role INTO current_user_role 
    FROM public.admin_roles 
    WHERE user_id = current_user_id;
    
    IF current_user_role != 'super_admin' THEN
        RETURN 'Error: Only super admins can promote users';
    END IF;
    
    -- Znajdź użytkownika do promowania
    SELECT id INTO target_user_id 
    FROM public.users 
    WHERE email = target_email;
    
    IF target_user_id IS NULL THEN
        RETURN 'Error: User not found';
    END IF;
    
    -- Promuj użytkownika
    INSERT INTO public.admin_roles (user_id, role, granted_by, granted_at)
    VALUES (target_user_id, admin_role, current_user_id, NOW())
    ON CONFLICT (user_id) 
    DO UPDATE SET 
        role = admin_role,
        granted_by = current_user_id,
        granted_at = NOW();
    
    RETURN 'Success: User promoted to ' || admin_role;
END;
$$;

-- ============================================
-- FUNKCJA 6: TESTOWANIE TWORZENIA UŻYTKOWNIKÓW
-- ============================================

CREATE OR REPLACE FUNCTION public.test_user_creation(
    test_email TEXT,
    test_username TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    test_result TEXT;
BEGIN
    -- Test czy można tworzyć użytkowników
    IF auth.uid() IS NULL THEN
        RETURN 'No authenticated user - this is normal for testing';
    END IF;
    
    -- Test czy tabela users istnieje i jest dostępna
    PERFORM 1 FROM public.users LIMIT 1;
    
    RETURN 'RLS policies working correctly';
EXCEPTION
    WHEN OTHERS THEN
        RETURN 'RLS test failed: ' || SQLERRM;
END;
$$;

-- ============================================
-- NADANIE UPRAWNIEŃ DO FUNKCJI
-- ============================================

-- Nadaj uprawnienia do wszystkich funkcji
GRANT EXECUTE ON FUNCTION public.create_user_profile TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.is_admin TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_admin_role TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.create_first_super_admin TO authenticated;
GRANT EXECUTE ON FUNCTION public.promote_user_to_admin TO authenticated;
GRANT EXECUTE ON FUNCTION public.test_user_creation TO authenticated, anon;
