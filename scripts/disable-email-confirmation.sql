-- KROK 1: Wyłącz potwierdzanie emaili
-- Uruchom to w SQL Editor w Supabase

-- Sprawdź obecne ustawienia
SELECT 
    raw_app_meta_data,
    raw_user_meta_data,
    email_confirmed_at,
    created_at
FROM auth.users 
LIMIT 5;

-- Wyłącz potwierdzanie emaili (metoda 1)
UPDATE auth.config 
SET enable_email_confirmations = false
WHERE id = 'auth';

-- Jeśli powyższe nie działa, spróbuj tej metody:
INSERT INTO auth.config (id, enable_email_confirmations)
VALUES ('auth', false)
ON CONFLICT (id) 
DO UPDATE SET enable_email_confirmations = false;

-- Sprawdź czy się zmieniło
SELECT * FROM auth.config;

-- Jeśli nadal nie działa, ustaw globalnie:
ALTER DATABASE postgres SET "app.settings.auth.enable_email_confirmations" = 'false';

-- Test - sprawdź czy można tworzyć użytkowników bez potwierdzenia
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM auth.config WHERE enable_email_confirmations = false) 
        THEN 'Email confirmation DISABLED ✅' 
        ELSE 'Email confirmation ENABLED ❌' 
    END as status;
