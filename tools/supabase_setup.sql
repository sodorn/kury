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

-- UWAGA: ten plik jest starsza kopia. Aktualna definicja: docs/supabase.sql.
-- Klucz z gry jest publiczny. Polityki ponizej (using (true)) pozwalaja
-- KAZDEMU z tym kluczem czytac wszystkie farmy i nadpisac kazda z nich.
-- Blokuja tylko kasowanie. Opis: DOKUMENTACJA_TECHNICZNA.txt, rozdzial 10.
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
