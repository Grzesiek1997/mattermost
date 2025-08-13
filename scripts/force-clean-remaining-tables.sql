-- KROK 1: Wyłącz wszystkie ograniczenia foreign key
SET session_replication_role = replica;

-- KROK 2: Usuń wszystkie polityki RLS z pozostałych tabel
DROP POLICY IF EXISTS "Users can view all profiles" ON public.users CASCADE;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.users CASCADE;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.users CASCADE;
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats CASCADE;
DROP POLICY IF EXISTS "Users can create chats" ON public.chats CASCADE;
DROP POLICY IF EXISTS "Users can view chat participants" ON public.chat_participants CASCADE;
DROP POLICY IF EXISTS "Users can join chats" ON public.chat_participants CASCADE;

-- KROK 3: Wyłącz RLS na tabelach
ALTER TABLE IF EXISTS public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.chats DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.chat_participants DISABLE ROW LEVEL SECURITY;

-- KROK 4: Usuń wszystkie triggery
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users CASCADE;
DROP TRIGGER IF EXISTS update_users_updated_at ON public.users CASCADE;
DROP TRIGGER IF EXISTS update_chats_updated_at ON public.chats CASCADE;

-- KROK 5: Usuń wszystkie funkcje
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.update_updated_at_column() CASCADE;
DROP FUNCTION IF EXISTS public.create_direct_chat_with_members(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS public.get_searchable_users(TEXT) CASCADE;

-- KROK 6: Usuń tabele w odpowiedniej kolejności (od zależnych do głównych)
DROP TABLE IF EXISTS public.chat_participants CASCADE;
DROP TABLE IF EXISTS public.chats CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;

-- KROK 7: Włącz z powrotem ograniczenia
SET session_replication_role = DEFAULT;

-- KROK 8: Sprawdź czy wszystko zostało usunięte
SELECT 
    'Pozostałe tabele:' as info,
    table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
    AND table_type = 'BASE TABLE';

SELECT 'Baza danych wyczyszczona!' as status;
