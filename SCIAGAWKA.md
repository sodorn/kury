# Ściągawka — wersje, git, baza danych

Wszystkie komendy PowerShell są pisane pod Windows PowerShell 5.1
i katalog `D:\GIT\kury`.

```
================================================================================
 1. JAK TO JEST POSKLADANE
================================================================================

  D:\GIT\kury                 zrodla na Twoim dysku
         |
         | git push / git pull
         v
  github.com/sodorn/kury      galaz "main"      = zrodla, najnowsze
                              galaz "gh-pages"  = ZBUDOWANA gra
                              galezie "v11.6-*" = zamrozone wydania
         |
         | GitHub Pages buduje strone z gh-pages
         v
  sodorn.github.io/kury       gra, w ktora gracie
         |
         | HTTPS, zapis i odczyt farm
         v
  Supabase                    baza danych z farmami graczy

  Zapisy graczy NIE sa w grze ani w repozytorium. Siedza w Supabase.
  Dlatego cofniecie wersji gry nie kasuje nikomu farmy.


================================================================================
 2. WERSJONOWANIE
================================================================================

  Numer:  11.6
          |  \__ druga cyfra: kazde wydanie (poprawki, interfejs, balans)
          \____ pierwsza: ZMIANA FORMATU ZAPISU - uwaga na stare farmy

  Numer widac na dole ekranu powitalnego w grze.
  Jesli jest inny, niz oczekujesz -> Ctrl+Shift+R (przegladarka trzyma stara).

  Kazde wydanie dostaje galaz:   v11.6-rozpakowanie-odpowiedzi
  Galaz jest zamrozona. "main" idzie dalej, ona zostaje.

  Numer siedzi w trzech plikach (docelowo bumpowane jedna komenda):
    core/util/game_data.gd   const VERSION     <- to czyta gra
    project.godot            config/version
    PROJECT_STATE.md         naglowek


================================================================================
 3. GIT - KOMENDY, KTORYCH UZYWASZ
================================================================================

  Sciagnac najnowsze zrodla:
      git pull

  Zobaczyc, na czym stoisz:
      git log --oneline -5
      git status

  Lista wszystkich wydan:
      git fetch
      git branch -r

  "Your local changes would be overwritten" - najczesciej project.godot,
  bo edytor Godota dopisuje tam swoje przy zamykaniu:
      git diff project.godot        <- zobacz, co to
      git checkout -- project.godot <- wyrzuc to
      git pull

  Chcesz zachowac swoja zmiane zamiast ja wyrzucac:
      git stash
      git pull
      git stash pop


================================================================================
 4. COFANIE SIE DO STARSZEJ WERSJI
================================================================================

  A) Tylko obejrzec stara wersje u siebie
     ------------------------------------
      git checkout v11.5-do-testow
      git checkout main              <- powrot

  B) COFNAC GRE NA STRONIE  (ten wazny przypadek)
     --------------------------------------------
     Nie trzeba niczego budowac. Galaz gh-pages trzyma gotowa gre
     z kazdego wydania osobno.

      git fetch
      git checkout gh-pages
      git log --oneline -10

     Zobaczysz:
      cf2253f Wersja 11.6 na GitHub Pages
      4003a82 Wersja 11.5 na GitHub Pages
      3f65932 Wersja 11.4 na GitHub Pages

     Bierzesz skrot wersji, do ktorej wracasz:
      git reset --hard 4003a82
      git push --force origin gh-pages
      git checkout main

     Minuta i strona chodzi na 11.5. Sprawdz numer na ekranie powitalnym.

     Od wersji 12.14 cofniecie dociera tez do OTWARTYCH kart: gra co
     minute sprawdza version.json na serwerze i sama sie przeladowuje,
     gdy numer sie rozni - w gore i w dol.

  C) WDROZYC NOWA WERSJE  (od 12.15 - SAMO)
     ---------------------------------------
     Push na main = GitHub sam testuje, buduje i wdraza
     (zakladka Actions -> "Buduj i wdroz gre", 5-8 minut).
     Otwarte karty przejda na nowa wersje same, w ciagu minuty.

     Recznie, tylko gdy automat nie dziala:
      tools/build_web.sh /tmp/web_build
      tools/deploy_pages.sh /tmp/web_build

  D) SAMEMU ZMIENIC CENE / CZAS / SZANSE
     ----------------------------------
      1. https://github.com/sodorn/kury/blob/main/data/balance.json
         (rasy: data/breeds.json)
      2. olowek "Edit this file"
      3. zmien liczbe - bez ruszania cudzyslowow i przecinkow
      4. "Commit changes..." -> "Commit changes"
      5. zakladka Actions: zielony = w grze, czerwony = nic nie
         wdrozono, a linie "BLAD: ..." mowia, co poprawic.
     Co oznacza kazda liczba: DOKUMENTACJA_TECHNICZNA.txt, rozdzial 7.

     Co to psuje: nic poza galezia gh-pages (sama zbudowana gra).
     Zrodla zostaja. Farmy graczy zostaja - sa w Supabase.


================================================================================
 5. BAZA DANYCH - CO TO WLASCIWIE JEST
================================================================================

  Supabase = hostowany PostgreSQL + gotowe REST API nad nim.
  Gra nie ma zadnego sterownika bazy. Wysyla zwykle zapytania HTTP.

  Projekt:   https://xrhehgxmaspopvvflcrn.supabase.co
  Tabela:    saves
  Panel:     supabase.com/dashboard -> wybierz projekt

  Tabela ma trzy kolumny:

      player_id   text    KOD FARMY, szesc cyfr. Klucz glowny.
      payload     jsonb   caly stan farmy jako JSON
      updated_at  bigint  czas uniksowy ostatniego zapisu

  Kod farmy = player_id. Kto zna kod, ten ma dostep do farmy.
  Zadnych hasel - swiadomy kompromis, zeby dalo sie przerzucic farme
  z telefonu na komputer bez zakladania konta.

  updated_at sluzy do rozstrzygania, kto wygrywa: gdy gra widzi na
  serwerze nowszy zapis niz u siebie, bierze ten z serwera.
  Wyjatek: gdy WPISUJESZ kod recznie, serwer wygrywa zawsze.

  KLUCZ. W pliku data/backend.json siedzi:
      sb_publishable_0aXf0Dby-fL_aOqkylCMcA_kUz7VG93

  To klucz PUBLIKOWALNY i on MA prawo byc jawny - siedzi w gotowej grze
  u kazdego gracza, kazdy moze go odczytac. Dziala jako rola "anon".
  Klucza sb_secret_... NIGDY nie wolno wpisac do gry ani wrzucic do repo.

  RLS (Row Level Security). Postgres domyslnie nie pokazuje roli anon
  niczego. Trzeba jawnie napisac polityki, co wolno. Nasze (plik
  docs/supabase.sql) mowia: anon moze czytac, wstawiac i nadpisywac
  wszystkie wiersze. Bez tych polityk odczyt zwraca pusta liste,
  a zapis leci 401 albo 403.

  Co gra naprawde wysyla:
      zapis:   POST /rest/v1/saves?on_conflict=player_id
               Prefer: resolution=merge-duplicates,return=minimal
      odczyt:  GET  /rest/v1/saves?player_id=eq.327733&select=payload,updated_at


================================================================================
 6. BAZA - JAK SPRAWDZIC, CZY ZYJE
================================================================================

  SPOSOB 1: z przegladarki, najszybszy
  ------------------------------------
  Wklej w pasek adresu (dziala takze na telefonie):

  https://xrhehgxmaspopvvflcrn.supabase.co/rest/v1/saves?select=player_id&limit=5&apikey=sb_publishable_0aXf0Dby-fL_aOqkylCMcA_kUz7VG93

  Widzisz JSON z kodami farm -> baza zyje i czyta.
  Widzisz blad albo nic nie przychodzi -> szukaj w punkcie 7.

  SPOSOB 2: z PowerShella
  -----------------------
      $key = "sb_publishable_0aXf0Dby-fL_aOqkylCMcA_kUz7VG93"
      $h   = @{ apikey = $key; Authorization = "Bearer $key" }
      $url = "https://xrhehgxmaspopvvflcrn.supabase.co/rest/v1/saves?select=player_id,updated_at"
      Invoke-RestMethod -Uri $url -Headers $h

  Jedna konkretna farma:
      $url = "https://xrhehgxmaspopvvflcrn.supabase.co/rest/v1/saves?player_id=eq.327733&select=player_id,updated_at"
      Invoke-RestMethod -Uri $url -Headers $h

  UWAGA: w PowerShellu 5.1 "curl" to nie jest prawdziwy curl, tylko alias
  na Invoke-WebRequest i zachowuje sie inaczej. Uzywaj Invoke-RestMethod.

  SPOSOB 3: przez GitHub Actions, bez wpisywania czegokolwiek
  -----------------------------------------------------------
      github.com/sodorn/kury/actions
      -> po lewej "Sprawdz farme w bazie"
      -> "Run workflow" -> wpisz kod farmy -> "Run workflow"
      -> odswiez, kliknij przebieg, kliknij "sprawdz"

  Powie, czy farma jest w bazie, kiedy byla zapisana i ile farm jest
  w ogole. Nie pokazuje zawartosci zapisu.

  SPOSOB 4: w panelu Supabase
  ---------------------------
      supabase.com/dashboard -> projekt -> SQL Editor

      select count(*) from public.saves;
      select player_id, to_timestamp(updated_at) as kiedy
      from public.saves order by updated_at desc limit 20;


================================================================================
 7. BAZA - CO SIE PSUJE I CO WTEDY
================================================================================

  OBJAW: gra mowi "Serwer nie odpowiada"
  --------------------------------------
  W panelu Kurnika, pod przyciskiem "Sprawdz polaczenie z serwerem",
  gra wypisuje dokladny powod z numerem. TEN NUMER JEST NAJWAZNIEJSZY -
  przyslij mi go, a nie sam fakt, ze nie dziala.

  Co znacza numery (to kody HTTPRequest z Godota):
      2   nie udalo sie polaczyc
      3   nie rozwiazano nazwy serwera (DNS)
      4   polaczenie zerwane
      5   blad szyfrowania TLS
      6   serwer nic nie odpowiedzial
      8   odpowiedz PRZYSZLA, ale nie dalo sie jej rozpakowac
          <- to byl blad z 21.11, naprawiony w 11.6
      13  minal czas oczekiwania

  Kody HTTP, jesli sie pojawia:
      401/403  klucz zly albo polityki RLS nie pozwalaja
      404      nie ma takiej tabeli
      409      brak klucza glownego na player_id

  PRZYCZYNA: darmowy projekt zasnal
  ---------------------------------
  Darmowy Supabase usypia projekt po TYGODNIU bez ruchu w bazie.
  Uspiony nie przyjmuje polaczen.

  Zabezpieczenie juz dziala: zadanie w GitHub Actions pinguje baze
  codziennie o 04:17 UTC. Jak przestanie dzialac, GitHub przysle Ci maila.
  Mozesz je odpalic recznie:
      github.com/sodorn/kury/actions
      -> "Utrzymaj baze Supabase przy zyciu" -> "Run workflow"

  Obudzic recznie mozna tez wchodzac do panelu Supabase i klikajac
  "Restore" / "Resume" na projekcie.

  PRZYCZYNA: tabela nie istnieje albo zle polityki
  ------------------------------------------------
  Wklej CALY plik docs/supabase.sql do SQL Editor w panelu Supabase
  i uruchom. Jest napisany tak, ze mozna go puscic ponownie bez szkody.

  Dwie rzeczy, na ktorych latwo sie przewrocic:
    - updated_at MUSI byc bigint, nie timestamptz (inaczej zapis leci 400)
    - player_id MUSI byc kluczem glownym (inaczej on_conflict leci 409)


================================================================================
 8. BAZA - KOPIA ZAPASOWA
================================================================================

  STAN NA DZIS: automatycznej kopii NIE MA. Jesli tabela zniknie,
  farmy przepadaja. Zrobienie tego automatem jest w kolejce
  (POMYSLY_BUGI_SUGESTIE.TXT, punkt 4.3).

  Recznie, z PowerShella - caly stan bazy do pliku:

      $key = "sb_publishable_0aXf0Dby-fL_aOqkylCMcA_kUz7VG93"
      $h   = @{ apikey = $key; Authorization = "Bearer $key" }
      $url = "https://xrhehgxmaspopvvflcrn.supabase.co/rest/v1/saves?select=*"
      $data = Invoke-RestMethod -Uri $url -Headers $h
      $stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
      $data | ConvertTo-Json -Depth 20 | Out-File "D:\GIT\kopie\saves_$stamp.json" -Encoding utf8

  (katalog D:\GIT\kopie trzeba raz zalozyc)

  Recznie, z panelu Supabase:
      SQL Editor -> select * from public.saves;  -> przycisk pobrania CSV

  Supabase na darmowym planie robi tez wlasne kopie, ale nie polegaj
  na nich przy czyms, na czym Ci zalezy.


================================================================================
 9. CZEGO NIE ROBIC
================================================================================

  - Nie wpisuj do backend.json klucza sb_secret_... Tylko publishable.
  - Nie rob "git push --force" na galezi main ani na galeziach v*.
    Force jest dopuszczalny WYLACZNIE na gh-pages (to sama zbudowana gra).
  - Nie kasuj galezi v* - to jedyne zamrozone kopie wydan.
  - Nie zmieniaj typu kolumny updated_at na timestamptz.
  - Nie kasuj polityk RLS "zeby bylo prosciej" - bez nich gra przestaje
    czytac i pisac.
```
