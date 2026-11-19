# PROJECT_STATE — Chicken Farm Simulator

Trwaly punkt odniesienia miedzy sesjami. Aktualizowany po kazdym etapie.

## Stan

- Aktualny etap: **ETAP 6 zakonczony** (wersja 7.0): ekonomia w zlotowkach,
  dziewiec ras, glod, choroby, szczepienia, lis, handel kurami w sklepie,
  rozbudowa inkubatora i dwa warunki wygranej.
- Wersje grafiki: **1.0** plaski wektor (galaz `v1.0-grafika-plaska`, commit 6ea3a3c),
  **2.1** pastelowa, miekkie kontury, zaokraglone sylwetki — aktualna.
- Wersje do cofniecia sie (galezie na GitHubie): `v1.0-grafika-plaska`,
  `v3.0-etap3`, `v4.0-zapis`, `v5.0-inkubator-rasy`, `v6.0-ekonomia-zdarzenia`,
  `v6.1-balans`, `v6.2-rasy`, `v7.0-budynki`.
- Gra stoi takze pod publicznym adresem (GitHub Pages, galaz `gh-pages`),
  dostepnym bez logowania: https://sodorn.github.io/kury/
- Silnik: Godot 4.7.2 stable (standard, GDScript), renderer Compatibility.
- Repo: `sodorn/kury`, galaz `main`. Claude pushuje, wlasciciel robi `git pull`.
- APK jeszcze nie powstal. Srodowisko Claude nie ma dostepu do serwera Google
  z Android SDK (`dl.google.com` odrzucone przez proxy), wiec eksport musi
  zrobic wlasciciel albo trzeba odblokowac te domene.

## Decyzje (nie zmieniac bez powodu)

- 2D, portrait, viewport 1080x1920, stretch `canvas_items` + `keep_width`
  (szerokosc stala 1080, wysokosc rosnie na wyzszych ekranach).
- Swiat farmy 1080x2400, wysrodkowany w pionie; widok 3/4 z sortowaniem po Y,
  bez siatki izometrycznej.
- **Co jest w scenie, a co w danych:** wszystko, co ma byc widoczne w edytorze
  (budynki, ich grafika, pozycje, obszary dotyku), stoi w `farm.tscn`.
  W `data/*.json` siedza teksty i parametry ekonomiczne. Budynki NIE sa
  tworzone w kodzie przy starcie — po otwarciu `farm.tscn` widac cala farme.
- Dane czytamy przez statyczna klase `GameData` (`core/util/game_data.gd`),
  a nie przez autoload. Autoload w identyfikatorze skryptu psuje kompilacje
  poza uruchomiona gra (testy, edytor). Autoloady zostaja tylko tam, gdzie
  trzymaja stan lub sygnaly: `Game`, `Events`.
- Logika gry w `core/` jako czyste klasy (RefCounted), bez wezlow i UI.
  Sceny tylko czytaja `Game.state` i sluchaja `Events`.
- Teksty w `data/strings.csv` (pl), uzywane przez `tr()`.
- Grafika wlasna (SVG, wektor), font Baloo 2 (licencja OFL, `assets/fonts/OFL.txt`).
  Styl 2.0: gradienty na kazdej duzej plaszczyznie, swiatlo z gory z lewej, miekkie
  cienie robione gradientem radialnym (nie filtrem — Godot renderuje SVG przez
  ThorVG, ktory filtrow nie obsluguje), cieplejsza paleta, wiecej drobiazgow.
- Paleta 2.1: pastelowa, ale nadal nasycona. Mocniejsze zmiekczenie (nasycenie
  x0.7, duze rozjasnienie) dalo obraz wyblakly i chorowity — nie powtarzac.
  Kontury: jeden cieply odcien #8A6A55 zamiast prawie czarnego brazu; to one
  decydowaly o wrazeniu "siermiezności". Przestrojenie zrobil jednorazowo
  tools/pastel_pass.py, wartosci sa juz zapisane w zrodlach.
- Rozmiary plotna i punkty zaczepienia sprite'ow sa stale — zmiana stylu nie rusza
  farm.tscn. Przy nowej grafice budynku trzymaj dotychczasowe wymiary.
- Dotyk: obiekty reaguja na `InputEventScreenTouch`; na PC mysz jest
  emulowana jako dotyk (ustawienie projektu).
- Testy uruchamiamy **jako sceny**, nie przez `-s`. Skrypt podany w `-s`
  kompiluje sie, zanim zarejestruja sie autoloady, i wtedy skrypty scen nie
  daja sie zaladowac (wezly traca skrypt bez widocznego bledu).
- Zapis gry (od ETAPU 4): `user://save.json` z polem `version` i migracjami.
  Format 3 (wersja 6.0): pieniadze ulamkowe, jaja liczone wedlug rasy,
  zwloki, choroby, poziom inkubatora, stan wygranej.
- Postep offline (od ETAPU 4): jedna funkcja `advance(state, dt)` dla ticka
  na zywo i nadrabiania; limit czasu offline w `balance.json`.

## Struktura

```
project.godot
data/        balance.json, buildings.json, strings.csv (+ wygenerowane .translation)
core/model/  farm_state.gd          stan gospodarstwa (czyste dane)
core/util/   game_data.gd           dostep do data/*.json (statyczny)
             number_format.gd
services/    events.gd, game.gd     (autoloady: Events, Game)
scenes/main/ main.tscn              scena startowa: Farm + Hud
scenes/farm/ farm.tscn/.gd          mapa z budynkami, drzewami, plotem
             building.tscn/.gd      budynek reagujacy na dotyk
scenes/ui/   hud/ (pasek licznikow), panels/ (panel budynku), theme/ (UiTheme, SafeArea)
assets/      sprites/world, sprites/buildings, ui, fonts, icon.svg
tests/       tests.tscn + run_tests.gd    logika, dane, scena farmy (headless)
             smoke_ui.tscn + smoke_ui.gd  klikanie w budynki + zrzuty ekranu
tools/       gen_ground.py          generator tla i przedniego plotu
             balance_model.py       model ekonomii: czy liczby maja sens
             build_web.sh           eksport wersji przegladarkowej
```

## Zapis po stronie serwera

- `services/cloud.gd` (autoload `Cloud`) wysyla i pobiera stan przez HTTP.
  Konfiguracja w `data/backend.json`; dopoki `enabled` = false, gra dziala
  wylacznie na zapisie lokalnym i nic sie nie zmienia.
- Protokol to kawalek REST-a Supabase (POST z `on_conflict`, GET z `eq.`),
  ale to zwykly HTTP — pod ten sam adres mozna podstawic dowolny serwer.
  Tabela: `tools/supabase_setup.sql`.
- Gracza rozpoznaje **kod farmy**: losowy identyfikator zapisany przy
  pierwszym uruchomieniu (`user://player_id.txt`), pokazywany w magazynie.
  Bez logowania i hasla — kto zna kod, ten ma dostep do tej farmy.
- Rozstrzyganie konfliktow: wygrywa nowszy zapis (po `saved_at`). Uwaga na
  przyszlosc: przy recznym wpisaniu cudzego kodu na urzadzeniu z nowszym
  zapisem lokalnym serwer przegra. Gdy dojdzie UI do przepisywania kodu,
  trzeba tam wymusic pobranie z serwera niezaleznie od czasu.
- Przetestowane w prawdziwej przegladarce przeciwko atrapie serwera
  (`tools/mock_backend.py` + sterowanie Chrome): stan trafia na serwer,
  a czyste urzadzenie z tym samym kodem farmy odtwarza go z serwera.
  Atrapa ma naglowki CORS, bo bez nich przegladarka odrzuca zapytania —
  prawdziwy Supabase tez je wysyla.

## Zapis lokalny (ETAP 4)

- `core/save_game.gd`: caly zapis i odczyt. Plik `user://save.json`, pole
  `version`, migracje w `_migrate`. Podnosic VERSION przy kazdej zmianie pol.
- Odczyt jest odporny: brak pliku, uszkodzony JSON, zapis z nowszej wersji gry
  i kura nieistniejacej juz rasy nie wywracaja gry (sa na to testy).
- `Game` zapisuje co 8 s oraz przy pauzie i zamknieciu. W przegladarce
  `user://` to IndexedDB, a Godot synchronizuje je dopiero w kolejnej klatce
  po zapisie — dlatego nie opieramy sie wylacznie na zapisie przy wyjsciu,
  bo zamykana karta moze nie zdazyc.
- Nadrabianie czasu: `Game._catch_up` wola `Simulation.advance` z liczba sekund
  od zapisu, przycieta do `offline.max_hours` z balance.json. Cofniety zegar
  daje zero (ujemny czas jest obcinany).
- Zapis jest lokalny dla przegladarki i urzadzenia: kazdy gracz ma swoja farme,
  nikt nie widzi cudzej. Wspolna gra na wielu urzadzeniach wymagalaby serwera
  i kont — swiadomie tego nie robimy.

## Inkubator, pisklęta i rasy (ETAP 4)

- Z jaj wlasnych kur wyklu wa sie pisklęta tej samej rasy: inkubator przyjmuje
  `eggs_per_chick` jaj i zajmuje jedno z `slots` miejsc (balance.json).
  Nie da sie wlozyc jaj rasy, ktorej nie ma sie w stadzie.
- Pisklę rosnie `grow_seconds` i dolacza do stada jako dorosla kura.
  Pisklęta chodza po wybiegu i zjadaja polowe paszy doroslej kury.
- Kura jedwabista slynie z wysiadywania jaj, wiec w grze przyspiesza
  inkubator (`incubation_bonus`).
- Osiem ras o rosnacej rzadkosci. Nowe odblokowuja sie same, gdy gospodarstwo
  spelni komplet warunkow z pola `unlock`: pieniadze, dzien gospodarstwa,
  liczba kur, zapas paszy i czasem posiadanie innej rasy.
- Dzien gospodarstwa to `day.seconds` z balance.json (domyslnie 10 minut),
  liczony tak samo na zywo i przy nadrabianiu czasu offline.
- Sklep pokazuje karte kazdej rasy. Zdjecie bierze z `assets/photos/<id>.jpg`,
  a gdy pliku nie ma — rysunek z wybiegu. Dzieki temu wrzucenie zdjec nie
  wymaga zmian w kodzie.

## Jak dziala rozgrywka (ETAP 3)

- `Simulation.advance(state, delta)` to jedyne miejsce liczace uplyw czasu.
  Tick na zywo wola ja z `Game._process`; w ETAPIE 4 ta sama funkcja nadrobi
  czas spedzony poza gra. Liczy krokami po 1 s, wiec wynik nie zalezy od tego,
  czy nadrabiamy godzine naraz czy sekunde po sekundzie (jest na to test).
- Kura znosi jajko co `egg_seconds` swojej rasy, o ile jest pasza. Bez paszy
  stado nie znosi i nic nie je, a gracz dostaje komunikat (sygnal `Events.notice`).
- Jaja ladują na wybiegu (`eggs_on_ground`) i trzeba je zebrac dotknieciem;
  dopiero wtedy trafiaja do magazynu (`eggs`) i mozna je sprzedac.
  Pelny wybieg (limit w `balance.json`) wstrzymuje znoszenie — to zacheta
  do zagladania do gry.
- Pozycje jaj zyja tylko w scenie, stan gry trzyma sama liczbe. Po wczytaniu
  wybieg rozstawia je na nowo w losowych miejscach.
- Panel budynku buduje swoja zawartosc w kodzie (`_build_content`), bo liczba
  przyciskow zalezy od liczby ras w `breeds.json`. Lista jest przewijana
  i ograniczona do polowy ekranu, zeby kolejne rasy nie wypchnely jej poza widok.
- Cztery rasy o rosnacej rzadkosci: leghorn, rhode, czubatka polska, ayam cemani.
  Rzadsze znosza wolniej, ale ich jaja sa wyraznie cenniejsze i same kury
  trzymaja wartosc przy sprzedazy (`sell_price` w breeds.json).
- Kury mozna kupowac w sklepie i sprzedawac w kurniku.

## Wykonane

- ETAP 1: architektura, plan MVP, repo.
- ETAP 2: projekt Godot, scena farmy (tlo, wybieg, 4 budynki, drzewa, krzaki),
  HUD z licznikami czytanymi z `Game.state`, panel budynku otwierany dotknieciem,
  motyw UI, obsluga bezpiecznego obszaru ekranu.
- ETAP 3: rasy kur w `breeds.json`, `Simulation.advance`, kury chodzace po
  wybiegu z dziobaniem, jaja do zbierania dotknieciem, sklep ze sprzedaza jaj
  i zakupem paszy oraz kur, panele budynkow z realnymi danymi, komunikat
  o braku paszy.
- ETAP 2 (poprawki po pierwszym uruchomieniu u wlasciciela):
  budynki przeniesione z kodu do sceny (wczesniej `farm.tscn` wygladala w
  edytorze na pusta lake); `Config` zastapiony przez `GameData`; obszary dotyku
  zapisane w scenie (znikly ostrzezenia przy wezlach `Shape`); testy przerobione
  ze skryptow `-s` na sceny.

## Weryfikacja ETAPU 2 (wykonana w srodowisku Claude, Linux)

- Import projektu w Godot 4.7.2: bez bledow.
- `tests/tests.tscn`: 217/217 OK (w tym: kazdy budynek z `buildings.json` jest
  w scenie farmy, ma grafike i wpis w danych).
- `tests/smoke_ui.tscn` (xvfb, renderer programowy), 32 sprawdzenia: scena sie
  renderuje, kazdy z 4 budynkow otwiera panel i zamyka go dotkniecie tla,
  kury chodza, jajko da sie zebrac dotknieciem, sklep sprzedaje i kupuje,
  karta zablokowanej rasy nie pozwala kupic, inkubator przyjmuje jaja,
  pisklę sie wykluwa, pojawia na wybiegu i dorasta, kurnik sprzedaje kure,
  komunikat o braku paszy sie pokazuje.
- Zapis w przegladarce sprawdzony realnie (Chrome sterowany playwright-core):
  po pierwszej sesji w IndexedDB lezy `save.json`, po ponownym wejsciu gra
  wstaje z zapisanym stanem (mniej paszy, jaja z poprzedniej sesji na wybiegu).
  UWAGA przy powtarzaniu takiego testu: `--virtual-time-budget` w Chrome ubija
  strone przed synchronizacja IndexedDB i daje falszywy wynik negatywny.
  Oba zestawy testow kasuja zapis na starcie i na koncu — inaczej kolejny bieg
  dziedziczylby stado i jaja po poprzednim.
  Test dymny wylacza `Game._process` — przy wolnym renderze symulacja zdazylaby
  znosic jaja w trakcie sprawdzen i wyniki bylyby losowe.
- Edytor uruchomiony na farm.tscn: brak ostrzezen przy wezlach.
- NIE sprawdzone: uruchomienie na Windows, na telefonie, wydajnosc, bezpieczny
  obszar na realnym urzadzeniu.

## Nastepne zadania

- Krotki samouczek na start (3-4 kroki) i przycisk "?" z zasadami.
- UI do przepisania kodu farmy na inne urzadzenie (z wymuszonym pobraniem
  z serwera, patrz uwaga wyzej).
- Zdjecia ras: podmiana plikow w assets/photos/, bez zmian w kodzie.
- Zdjecia ras w panelu sklepu: wlasciciel dostarcza pliki, Claude nie ma
  dostepu do sieci poza GitHubem i rejestrami pakietow, wiec sam ich nie pobierze.
  Wymagania: PNG, jeden ptak na plik, licencja pozwalajaca na uzycie
  (np. Wikimedia Commons), do tego plik z podpisami autorow do ekranu "o grze".

## Znane problemy / uwagi

- Docelowa grafika: wlasciciel chce poziomu renderowanej grafiki 2.5D z gier
  mobilnych. Recznie pisanym SVG tego nie osiagniemy — droga to gotowa paczka
  assetow albo obrazki generowane i wstawiane jako PNG z przezroczystoscia.
  Na razie zostaje grafika wlasna 2.1.
- Liczniki HUD mieszcza ok. 6 cyfr; skracanie duzych liczb (1,2 mln) w ETAPIE 5.
- Eksport Android (ETAP 7): potwierdzic, ze `data/*.json` trafiaja do paczki
  (w razie potrzeby filtr `*.json` w presecie eksportu); potwierdzic wersje
  Android SDK wymagane przez Godot 4.7.
- Ikona aplikacji (`assets/icon.svg`) jest robocza.

## Komendy

```
tools/build_web.sh <katalog>          # wersja do przegladarki
python3 tools/pastel_pass.py          # jednorazowe przestrojenie palety (juz wykonane)
godot --headless --path . --import
godot --headless --path . res://tests/tests.tscn
godot --path . res://tests/smoke_ui.tscn -- <katalog_na_zrzuty>
python3 tools/gen_ground.py
```

## Ekonomia i zdarzenia (ETAP 5, wersja 6.0)

### Pieniadze i ceny

- Wszystkie kwoty sa w **zlotowkach, ulamkowo** (`money: float`), bo jajko moze
  kosztowac 40 groszy. Wyswietlanie wylacznie przez `NumberFormat.money`.
- **Czternascie ras**, drabinka cen z krokiem okolo 1,3x: 36, 48, 65, 85,
  110, 145, 190, 250, 330, 450, 650, 950, 1600, 3000 zl. Rownomierny krok
  jest celowy — przy dziewieciu rasach skok z 1400 na 6000 zl wygladal jak
  blad i mylil sie z progiem odblokowania.
- Dolny i srodkowy odcinek zgadza sie z polskimi ogloszeniami (nioska 36 zl,
  kochin miniaturowy 80 zl, karzelki 100 zl, silka 100 zl). Gorne rasy sa
  rozciagniete wzgledem rynku, bo gra potrzebuje rozpietosci; Cemani
  z rodowodem potrafi kosztowac i 6 tys. zl, wiec 3000 zl miesci sie
  w realiach.
- **Sprzedaz kury = 70% ceny zakupu** (czyli 30% taniej). Jest na to test,
  wiec przy zmianie ceny trzeba zmienic obie liczby. Jedna opcja sprzedazy,
  bez miesa: za **chora** kure skup placi `economy.sick_sell_share` tej kwoty.
  Sprzedaz bierze najpierw zdrowe sztuki, zeby kwota na przycisku zawsze
  zgadzala sie z tym, co gracz dostanie.
- Jajka: od 0,40 zl (leghorn) do 1,00 zl (cemani), krok rowny miedzy rasami. Celowo waski rozstrzal —
  wartosc siedzi w kurze, nie w jajku. Drogie rasy nios a rzadziej, wiec na
  samych jajach wychodza **gorzej** od leghorna; zarabia sie na sprzedazy
  odchowanych mlodych.
- Pasza: worek 25 kg za 60 zl (2,40 zl/kg, tyle co naprawde). **Kazda kura
  zjada tyle samo**, niezaleznie od rasy; pisklę polowe porcji.

### Model ekonomii

- `tools/balance_model.py` liczy oplacalnosc kazdej rasy i symuluje rozsadnego
  gracza. Uruchamiac po **kazdej** zmianie cen w `data/*.json`.
- Stan na wersje 7.0: pelna kolekcja ras po ~23,5 h gry, milion zlotych po
  ~26,3 h. Nowa rasa odblokowuje sie mniej wiecej co dwie godziny gry.
  Rozbudowy budynkow kosztuja lacznie okolo 150 tys. zl i to one daja
  pieniadzom drugie zastosowanie obok kupowania kolejnych ras. Oba warunki wygranej wypadaja prawie rownoczesnie — o to chodzilo.
- Model liczy takze lisa i szczepienia, bo jedno i drugie realnie spowalnia
  gre. Bez nich wychodzily liczby o kilka godzin za dobre.
- Zarabia sie nie na jajach, tylko na **hodowli**: z 6 jaj wyklu wa sie pisklę,
  ktore po odchowaniu sprzedaje sie za polowe ceny rasy. Dlatego droga rasa
  oplaca sie mimo tej samej paszy. Jaja same w sobie ledwie pokrywaja pasze.
- Waskim gardlem jest liczba miejsc w inkubatorze, stad rozbudowa:
  3 -> 6 (1200 zl) -> 10 (12 000 zl) -> 15 (90 000 zl).

### Zdarzenia

- **Glod**: po `hunger.grace_minutes` bez paszy kury padaja po jednej co
  `death_interval_seconds` i zostawiaja zwloki, ktore rozkladaja sie
  `corpse_seconds`. Pozycja zwlok siedzi w stanie gry, nie w scenie — po
  wznowieniu leza tam, gdzie padly.
- **Choroby**: `disease.chance_per_hen_hour` na kure. Chora nie znosi jaj
  i po `death_minutes` pada. Lek leczy jedna kure (wybiera najdrozsza chora).
  Szczepienie chroni do konca zycia, ale **tylko kury zyjace w chwili
  szczepienia** — mlode wyklute pozniej trzeba zaszczepic osobno.
- **Lis**: raz na `fox.min_hours`-`max_hours` zabiera 20-90% stada, ale nigdy
  calego i nie przychodzi do stada mniejszego niz `min_hens`. Zwlok nie ma,
  bo lis zabiera kury ze soba. Przebiega przez wybieg (scenes/farm/fox.tscn).
- **Bezpiecznik offline**: przy nadrabianiu czasu laczne straty (glod +
  choroby + lis) nie moga przekroczyc `hunger.offline_max_share` stada.
  Bez tego powrot po dobie oznaczalby pusty wybieg i koniec zabawy.

### Budynki i ich rozbudowa

- Kazdy budynek na mapie ma swoja sciezke rozbudowy w `balance.json`
  (`buildings`), a inkubator swoja wlasna (`incubator.upgrades`):
  - **kurnik** — pojemnosc stada, 20 -> 40 -> 70 -> 120. Liczy **tylko
    dorosle kury**; pisklęta siedza przy inkubatorze. Gdy kurnik jest pelny,
    podrosniete pisklę czeka, zamiast znikac. Pierwotnie liczylem do limitu
    takze jaja w inkubatorze — to wiazalo gracza podwojnie i wydluzalo gre
    o kilka godzin bez zadnego zysku dla rozgrywki.
  - **magazyn** — hurt na pasze: wiekszy worek i nizsza cena za kilogram.
  - **obrona przed lisem** — plot, potem pies. Mnozy przerwe miedzy wizytami.
- Rozbudowy sa opcjonalne, ale bez kurnika stado staje w miejscu.

### Lis: wizyta z oknem na reakcje

- Wizyta ma dwa etapy. Przez `fox.visit_seconds` lis biega po wybiegu
  i **jeszcze nic nie zabiera** — wtedy gracz moze go przegonic, trafiajac
  w niego `fox.scare_taps` razy. Dopiero po tym czasie zabiera lup.
- Pod nieobecnosc gracza nie ma kogo czekac, wiec strata liczy sie od razu.
- Dzieki temu lis przestal byc kara bez odpowiedzi, a obecnosc przy grze
  zaczela cos znaczyc.

### Uplyw czasu — trzy przypadki, jeden mechanizm

- Symulacje prowadzi **zegar scienny**, nie delta klatki. Przegladarka zwalnia
  petle gry w karcie w tle: zmierzone w Chrome, po stu sekundach w tle gra
  naliczala sobie 21% tego czasu. Po poprawce 99%.
- Gra zamknieta: `_apply_elapsed` z roznicy wzgledem `saved_at`, limit
  `offline.max_hours` (72 h **rzeczywiste**).
- **Poza gra czas plynie `offline.speed_divider` razy wolniej** (60x), zeby
  noc nie zmieniala gospodarstwa nie do poznania: stado nie pada z glodu
  i lis nie wynosi polowy kurnika, ale tez nie ma co liczyc na kokosy
  z samego czekania. Osiem godzin snu to okolo osmiu minut gry.
- Dziura dluzsza niz `MAX_LIVE_STEP` (30 s) idzie ta sama sciezka co gra
  zamknieta. Wczesniej byla po prostu wyrzucana — i to byl blad, ktory
  Tomek zobaczyl na telefonie: po zminimalizowaniu przegladarki strona
  zamraza sie calkiem, a po powrocie nic sie nie dzialo.
- Karta w tle (`DisplayServer.window_is_focused()` = false): czas zbiera sie
  w `_away_seconds` i rozlicza jednym wywolaniem po powrocie. Nie wolno
  rozliczac go co klatke — odstepy ponizej sekundy przepadaja, a komunikat
  powitalny leci w kolko.
- **Offline jaja ida prosto do magazynu**, z pominieciem wybiegu. Wybieg
  miesci `run.max_eggs_on_ground` jaj, wiec bez tego po kilkunastu minutach
  nieobecnosci kury przestawalyby niesc i caly nocny urobek przepadalby.
  Zbieranie jaj palcem zostaje dla gry na zywo.

### Wygrana

- Dwa warunki, oba w `balance.json`: `win.money` (milion zlotych) albo
  `win.collection` (po jednej kurze kazdej rasy). Stan wygranej jest zapisany,
  wiec okno pokazuje sie raz. Gra toczy sie dalej.

### Wybieg

- Obszar chodzenia kur siedzi w `balance.json` (`run.area`) i czyta go
  **zarowno symulacja** (kladzie zwloki), **jak i scena**. Przy zmianie
  trzeba przegenerowac tlo (`tools/gen_ground.py` — stala `RUN`) i przesunac
  `FenceFront` w `farm.tscn`. Te trzy miejsca musza sie zgadzac.
- Kury i jaja sa o 40% wieksze niz w 5.0 (latwiej trafic palcem).
- `run.max_visible_hens` ogranicza liczbe rysowanych kur; przy wiekszym stadzie
  scena pokazuje proporcjonalna probke, ale po jednej sztuce kazdej rasy.
  Chore kury pokazywane sa zawsze, bo to one wymagaja reakcji.

### Karta rasy zablokowanej

- Warunek odblokowania i cena to **dwie osobne linijki**. Samo "3 000 zl"
  w miejscu, gdzie inne karty maja "Kup za 80 zl", czyta sie jak cena kury —
  Tomek tak to odczytal i zglosil jako bledny balans.

### Zdjecia ras w sklepie

- Karta rasy pokazuje `assets/photos/<id>.jpg`, a gdy pliku nie ma — rysunek
  z wybiegu. Dzieki temu gra dziala bez zdjec. Lista nazw plikow i wymagania:
  `assets/photos/CZYTAJ_TO.md`.
