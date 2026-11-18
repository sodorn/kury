# Serwer na zapisy gry — instrukcja krok po kroku

Po co: żeby postęp gry nie siedział w przeglądarce, tylko na serwerze.
Wtedy ta sama farma działa na telefonie i na komputerze, a wyczyszczenie
przeglądarki niczego nie kasuje.

Czas: około 20 minut. Nie trzeba karty kredytowej.

---

## Czy to jest darmowe i wieczne?

Darmowe — tak. Wieczne — prawie, ale jest jeden haczyk.

Plan Free w Supabase jest stały i nie wymaga karty. Dostajesz dwa projekty,
500 MB bazy, 5 GB transferu miesięcznie. Zapis gry to jakieś 2 KB, więc
500 MB starczy na około 250 tysięcy zapisów. Limitów nie dotkniesz.

**Haczyk: projekt na planie Free zostaje wstrzymany po 7 dniach bez ruchu
w bazie.** Liczy się każde zapytanie do bazy — czyli każde wejście do gry.
Jeśli ty albo dziewczyna zagracie choć raz w tygodniu, projekt nigdy się
nie wstrzyma. Jeśli odpuścicie na dwa tygodnie, projekt zaśnie: dane
zostają, ale baza przestaje odpowiadać, dopóki nie klikniesz "Restore"
w panelu. Od wstrzymania rusza 90-dniowy licznik do skasowania projektu.

Czyli: gra raz w tygodniu = działa w nieskończoność za darmo.
Dłuższa przerwa = jedno kliknięcie po powrocie.

Jeśli kiedyś to zacznie przeszkadzać, Pro za 25 USD miesięcznie znosi
wstrzymywanie. Dla gry dla dwóch osób to wyrzucanie pieniędzy.

---

## Krok 1 — załóż konto

1. Wejdź na https://supabase.com
2. Kliknij **Start your project** (prawy górny róg).
3. Zaloguj się przez GitHub — masz już konto `sodorn`, więc to jedno
   kliknięcie. Pojawi się ekran "Authorize Supabase" → **Authorize**.

## Krok 2 — stwórz projekt

1. Kliknij **New project**.
2. Jeśli poprosi o organizację: **New organization**, nazwa dowolna
   (np. `sodorn`), plan **Free**.
3. Wypełnij:
   - **Name:** `kury`
   - **Database Password:** kliknij **Generate a password** i zapisz je
     w menedżerze haseł. Do gry nie będzie potrzebne, ale bez niego nie
     wejdziesz później do bazy przez SQL-a z zewnątrz.
   - **Region:** `Central EU (Frankfurt)` — najbliżej Polski.
4. **Create new project**. Stawianie bazy trwa 2-3 minuty.

## Krok 3 — stwórz tabelę

1. W lewym menu kliknij ikonę **SQL Editor** (kartka z napisem SQL).
2. Kliknij **New query**.
3. Wklej dokładnie to:

```sql
create table if not exists public.saves (
  player_id  text primary key,
  payload    jsonb not null,
  updated_at bigint not null default (extract(epoch from now())::bigint)
);

alter table public.saves enable row level security;

create policy "gra moze czytac swoj zapis"
  on public.saves for select
  using (true);

create policy "gra moze zapisywac"
  on public.saves for insert
  with check (true);

create policy "gra moze nadpisywac"
  on public.saves for update
  using (true) with check (true);
```

4. Kliknij **Run** (albo Ctrl+Enter). Na dole ma się pojawić
   **Success. No rows returned**. Jeśli jest czerwony błąd — zrób zrzut
   ekranu i wyślij mi.

To samo siedzi w pliku `tools/supabase_setup.sql` w repo, gdybyś wolał
wkleić z pliku.

## Krok 4 — przepisz mi dwie rzeczy

1. W lewym menu na dole: **Project Settings** (zębatka).
2. Wejdź w **API Keys** (albo **API**, zależnie od wersji panelu).
3. Skopiuj i wyślij mi:

```
Project URL:  https://xxxxxxxxxxxx.supabase.co
anon public:  eyJhbGciOi... (długi ciąg znaków)
```

**Klucz `anon public` wyślij spokojnie — jest przeznaczony do tego, żeby
siedzieć w aplikacji u gracza.** Natomiast klucza oznaczonego
`service_role` / `secret` NIE wysyłaj nigdzie i nikomu. Ten jeden daje
pełną władzę nad bazą.

## Krok 5 — reszta jest po mojej stronie

Wpiszę te dwie wartości do `data/backend.json`, przestawię `enabled` na
`true`, przebuduję grę i wgram na stronę. Potem sprawdzę w prawdziwej
przeglądarce, czy zapis faktycznie ląduje na serwerze — tak jak przy
poprzednich etapach, na atrapie serwera.

---

## Jak to będzie działać od strony gracza

Każde urządzenie dostaje przy pierwszym uruchomieniu **kod farmy** —
coś w rodzaju `7K73-ABGC-63CK`. Widać go w Magazynie. Kod jest
identyfikatorem konta: kto go zna, ten ma dostęp do tej farmy.

Żeby grać tą samą farmą na telefonie i na komputerze, trzeba będzie
przepisać kod z jednego urządzenia na drugie. **Okienka do wpisania kodu
jeszcze nie ma** — to następna rzecz do zrobienia po podpięciu serwera.
Bez niego każde urządzenie ma własną, osobną farmę, tyle że trzymaną
na serwerze zamiast w przeglądarce.

Uwaga na przyszłość, o której pamiętam: przy wpisywaniu cudzego kodu na
urządzeniu, które ma nowszy zapis lokalny, trzeba wymusić pobranie
z serwera — inaczej wygra lokalny i przepisze cudzą farmę. Zrobię to
przy okazji tego okienka.

---

## Gdyby Supabase ci nie pasował

Gra gada z serwerem zwykłym HTTP-em (POST i GET z JSON-em). Supabase
jest tylko najprostszą opcją bez stawiania czegokolwiek. Pod ten sam
adres można podstawić własny serwer — jeśli masz gdzieś VPS-a albo
chcesz to trzymać u siebie, powiedz, przepiszę adres i napiszę
kilkadziesiąt linii backendu. Protokół jest w `services/cloud.gd`.
