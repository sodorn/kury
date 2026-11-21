-- Tabela zapisow gry dla "Symulatora Hodowli Kurczakow".
-- Wklej calosc do SQL Editor w panelu Supabase i uruchom.
--
-- Dwie rzeczy, na ktorych latwo sie przewrocic:
--  1. updated_at MUSI byc bigint. Gra wysyla czas uniksowy jako liczbe;
--     kolumna timestamptz odrzucilaby zapis kodem 400.
--  2. Bez polityk RLS odczyt zwraca pusta liste, a zapis leci 401/403.
--     Klucz publishable dziala jako rola anon i widzi tylko to, na co
--     pozwalaja polityki.

create table if not exists public.saves (
  player_id  text   primary key,   -- primary key daje UNIQUE dla on_conflict
  payload    jsonb  not null,
  updated_at bigint not null
);

alter table public.saves enable row level security;

-- Kto zna szesciocyfrowy kod farmy, ten ma do niej dostep. Zadnych hasel.
-- Swiadomy kompromis: kazdy z kluczem z gry moze czytac i nadpisywac zapisy.
drop policy if exists kury_select on public.saves;
create policy kury_select on public.saves
  for select to anon using (true);

drop policy if exists kury_insert on public.saves;
create policy kury_insert on public.saves
  for insert to anon with check (true);

drop policy if exists kury_update on public.saves;
create policy kury_update on public.saves
  for update to anon using (true) with check (true);

grant select, insert, update on public.saves to anon;
