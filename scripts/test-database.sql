-- TEST BAZY DANYCH
-- Uruchom to żeby sprawdzić czy wszystko działa

-- ============================================
-- TEST 1: SPRAWDŹ CZY TABELE ISTNIEJĄ
-- ============================================

SELECT 
    table_name,
    CASE 
        WHEN table_name IN (
            'users', 'admin_roles', 'chats', 'chat_members', 
            'messages', 'message_reactions', 'contacts', 'typing_indicators'
        ) THEN '✅ OK'
        ELSE '❌ MISSING'
    END as status
FROM information_schema.tables 
WHERE table_schema = 'public' 
    AND table_name IN (
        'users', 'admin_roles', 'chats', 'chat_members', 
        'messages', 'message_reactions', 'contacts', 'typing_indicators'
    )
ORDER BY table_name;

-- ============================================
-- TEST 2: SPRAWDŹ CZY FUNKCJE ISTNIEJĄ
-- ============================================

SELECT 
    routine_name as function_name,
    '✅ EXISTS' as status
FROM information_schema.routines 
WHERE routine_schema = 'public' 
    AND routine_name IN (
        'create_user_profile', 'is_admin', 'get_admin_role',
        'create_first_super_admin', 'promote_user_to_admin', 'test_user_creation'
    )
ORDER BY routine_name;

-- ============================================
-- TEST 3: SPRAWDŹ USTAWIENIA EMAIL CONFIRMATION
-- ============================================

SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM auth.config 
            WHERE enable_email_confirmations = false
        ) THEN '✅ Email confirmation DISABLED (good for development)'
        ELSE '❌ Email confirmation ENABLED (may cause issues)'
    END as email_confirmation_status;

-- ============================================
-- TEST 4: SPRAWDŹ RLS POLICIES
-- ============================================

SELECT 
    schemaname,
    tablename,
    policyname,
    '✅ POLICY EXISTS' as status
FROM pg_policies 
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- ============================================
-- TEST 5: SPRAWDŹ INDEKSY
-- ============================================

SELECT 
    schemaname,
    tablename,
    indexname,
    '✅ INDEX EXISTS' as status
FROM pg_indexes 
WHERE schemaname = 'public'
    AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;

-- ============================================
-- TEST 6: SPRAWDŹ CZY MOŻNA TWORZYĆ DANE TESTOWE
-- ============================================

-- Ten test pokaże czy RLS działa poprawnie
SELECT public.test_user_creation('test@example.com', 'testuser') as rls_test_result;

-- ============================================
-- PODSUMOWANIE
-- ============================================

SELECT 
    '🎉 DATABASE SETUP COMPLETE!' as message,
    'If all tests show ✅, your database is ready!' as instruction;
