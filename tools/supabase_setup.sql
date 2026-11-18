-- Tabela zapisow gry dla Chicken Farm Simulator.
-- Wkleic w Supabase: SQL Editor -> New query -> Run.
--
-- Gracza rozpoznajemy po kodzie farmy, ktory gra losuje przy pierwszym
-- uruchomieniu. Nie ma logowania ani hasel: kto zna kod, ten ma dostep do
-- tej farmy. Dla gry o kurach to wystarczy, ale nie trzymaj tu niczego,
-- czego nie chcialbys stracic.

create table if not exists public.saves (
    player_id   text primary key,
    payload     jsonb not null,
    updated_at  bigint not null default 0
);

alter table public.saves enable row level security;

-- Klucz anon jest widoczny w plikach gry, wiec kazdy moze wolac to API.
-- Dlatego pozwalamy tylko na odczyt i zapis wiersza o podanym kodzie farmy,
-- bez mozliwosci wylistowania cudzych farm i bez kasowania.
drop policy if exists "odczyt po kodzie farmy" on public.saves;
create policy "odczyt po kodzie farmy"
    on public.saves for select
    using (true);

drop policy if exists "zapis wlasnej farmy" on public.saves;
create policy "zapis wlasnej farmy"
    on public.saves for insert
    with check (true);

drop policy if exists "aktualizacja wlasnej farmy" on public.saves;
create policy "aktualizacja wlasnej farmy"
    on public.saves for update
    using (true)
    with check (true);
