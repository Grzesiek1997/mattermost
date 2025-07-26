-- KROK 1: Wyłącz potwierdzanie emaili
-- Uruchom to w SQL Editor w Supabase

-- Sprawdź obecne ustawienia auth
SELECT 
    raw_app_meta_data,
    raw_user_meta_data,
    email_confirmed_at,
    created_at
FROM auth.users 
LIMIT 5;

-- Wyłącz potwierdzanie emaili - metoda 1
UPDATE auth.config 
SET enable_email_confirmations = false;

-- Jeśli powyższe nie działa, spróbuj tej metody:
INSERT INTO auth.config (id, enable_email_confirmations)
VALUES ('default', false)
ON CONFLICT (id) 
DO UPDATE SET enable_email_confirmations = false;

-- Sprawdź czy się zmieniło
SELECT * FROM auth.config;

-- Alternatywna metoda - ustaw w systemie
ALTER SYSTEM SET "app.settings.auth.enable_email_confirmations" = 'false';

-- Test - sprawdź status
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM auth.config WHERE enable_email_confirmations = false) 
        THEN 'Email confirmation DISABLED ✅' 
        ELSE 'Email confirmation ENABLED ❌ - need to disable manually' 
    END as status;

-- Jeśli nadal nie działa, sprawdź tabele auth
SELECT table_name FROM information_schema.tables WHERE table_schema = 'auth';
