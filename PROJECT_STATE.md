# PROJECT_STATE — Chicken Farm Simulator

Trwaly punkt odniesienia miedzy sesjami. Aktualizowany po kazdym etapie.

## Stan

- Aktualny etap: **ETAP 10** (wersja 12.3): nazwane poziomy rozbudowy
  kurnika, inkubatora i magazynu; choroba na tej samej kostce co lis.
- Wersja 12.2: groteskowa smierc kur —
  urwane glowy, kaluze krwi, kontrast z cukierkowa oprawa jest celowy.
- Wersja 12.1: lis przebudowany od zera —
  zawsze odchodzi, nigdy nie ma go kilku naraz, przegania sie go palcem,
  a pies jest widoczny i goni.
- Wersja 12.0: plot i pies rozdzielone na dwie niezalezne sciezki
  obrony, format zapisu 6 z przeliczeniem starych farm.
- Wersja 11.6: znaleziona i naprawiona przyczyna "serwer nie odpowiada"
  przy wczytywaniu farmy z kodu — Godot nie rozpakowywal odpowiedzi
  serwera (kod 8).
- Wersja 11.5: numer wersji widac na ekranie powitalnym.
  Ustalony zamysl ekonomii: jajka to grosze na pasze, zarabia sie na
  sprzedazy wyhodowanych drogich kur, hamulcem jest czas rozrodu.
- Wersja 11.4: uwagi kolegow Tomka
  rozpisane w `POMYSLY_BUGI_SUGESTIE.TXT`, naprawione bledy inkubatora
  i panelu, numery poziomow rozbudowy, baza Supabase budzona codziennie.
- Wersja 11.3: jeden czas na wszystko, lis z twarda gwarancja, wiekszy
  wybieg i zbieranie jaj garsciami.
- Wersja 10.x: kury i koguty. Kura
  znosi jaja tylko wtedy, gdy na farmie jest kogut jej rasy. Do tego duzo
  tansze rozbudowy, kurnik do 260 ptakow, trzy jaja na pisklę zamiast
  szesciu, szczepienie za stala setke i czesciej przychodzacy lis.
- Wersja 9.0: sklep bez blokad — siedemnascie ras do kupienia od pierwszej
  minuty, a hamulcem balansu jest czas odchowu, nie prog odblokowania.
- Wersje grafiki: **1.0** plaski wektor (galaz `v1.0-grafika-plaska`, commit 6ea3a3c),
  **2.1** pastelowa, miekkie kontury, zaokraglone sylwetki — aktualna.
- Wersje do cofniecia sie (galezie na GitHubie): `v1.0-grafika-plaska`,
  `v3.0-etap3`, `v4.0-zapis`, `v5.0-inkubator-rasy`, `v6.0-ekonomia-zdarzenia`,
  `v6.1-balans`, `v6.2-rasy`, `v7.0-budynki`, `v8.0-serwer`,
  `v8.1-ekran-startowy`, `v9.0-sklep-bez-blokad`, `v10.0-koguty`, `v10.1-plot-i-kurnik`, `v10.2-zdarzenia`, `v10.3-lis-i-jaja`, `v10.4-kwoty-i-czas`, `v11.0-czas-i-wybieg`, `v11.1-klawiatura-kodu`, `v11.2-widoczne-komunikaty`, `v11.3-diagnoza-serwera`, `v11.4-uwagi-kolegow`, `v11.5-do-testow`, `v11.6-rozpakowanie-odpowiedzi`, `v12.0-plot-i-pies`, `v12.1-lis-od-nowa`, `v12.2-groteska`, `v12.3-poziomy`.
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

## WERSJA 12.3: nazwane poziomy rozbudowy, choroba jak lis

CHOROBA dostala dokladnie te sama logike co lis, tylko dwa razy czesciej:
kostka co 30 minut realnych z szansa 1/3 w grze aktywnej, co 12 godzin
z szansa 1/6 w nieaktywnej (lis: 60 minut i 24 godziny). Poprzednie
"kolejna kura co minute" bylo za czeste i wlasciciel slusznie to zglosil.

DRABINKI ROZBUDOWY wydluzone i nazwane. Kazdy poziom ma teraz nazwe,
ktora widac na przycisku i w wierszu "Poziom":

    KURNIK     20 -> 35 -> 55 -> 80 -> 110 -> 150 -> 200 -> 270 -> 360 -> 500
               powiekszony, sredni, duzy, bardzo duzy, dwukondygnacyjny,
               hala drobiowa, wielka hala, ferma, ferma przemyslowa
               400 / 1,2k / 3k / 7k / 15k / 30k / 60k / 120k / 250k

    INKUBATOR   3 -> 6 -> 10 -> 16 -> 24 -> 34 -> 48 -> 66 -> 90
               wiekszy, sredni, duzy, bardzo duzy, dwukomorowy,
               hodowlany, przemyslowy, wylegarnia
               300 / 1k / 2,8k / 7k / 16k / 36k / 80k / 180k

    MAGAZYN    25 -> 60 -> 150 -> 400 -> 1000 -> 2500 -> 6000 -> 15000 kg
               wiekszy, sredni, duzy, bardzo duzy, silos, wielki silos,
               elewator
               300 / 1k / 3,5k / 10k / 26k / 75k / 220k

Zasady, ktorych pilnuje nowy test `_test_upgrade_ladders`:
- kazdy poziom ma nazwe i jest ona przetlumaczona,
- kazdy kolejny poziom jest drozszy i cos realnie dodaje,
- koszt JEDNOSTKI (miejsca, slotu, kilograma) rosnie z poziomem — inaczej
  oplacaloby sie przeskakiwac srodek drabinki. Na tym tescie wylozyly sie
  pierwsze ceny silosu i elewatora i trzeba je bylo podniesc,
- kilogram paszy tanieje z kazdym poziomem magazynu,
- pelny inkubator (90) miesci sie w pelnym kurniku (500) — pisklęta maja
  gdzie trafic.

## WERSJA 12.2: groteska zamiast stonowanej smierci

Wlasciciel wyjasnil zamysl, ktory wczesniej zle odczytalem. Pastelowa,
cukierkowa oprawa nie jest powodem, zeby lagodzic smierc kur — jest
powodem, zeby tego NIE robic. Kontrast miedzy slodka grafika a tym, co
zostaje po lisie, jest zartem. Ta sama mysl stoi za skupem chorych kur
do McDonalda za 5 zl.

Wprowadzone:
- `hen_dead.svg` przerobiona: kura bez glowy, kikut szyi z rana, strugi
  krwi po pierzu, kaluza splaszczona w poziomie (bo na wybieg patrzymy
  pod katem), rozsypane piora, jedno zakrwawione.
- Nowy `hen_head.svg`: urwana glowa, oko na krzyzyk, poszarpana szyja.
  W chwili napasci wylatuje z kury, kreci sie w locie, laduje na wybiegu
  i powoli znika razem z krwia. Najwyzej trzy naraz, zeby przy duzym
  lupie nie robil sie deszcz glow.
- Krew z chmurki zrobila sie strumieniem: 70 czastek zamiast 30, waski
  rozrzut (55 zamiast 110 stopni), predkosc do 760 zamiast 470.

Rejestr jest kreskowkowy, nie realistyczny — o to chodzi, zeby to bylo
smieszne, a nie paskudne.

## WERSJA 12.1: lis przebudowany od zera

Wlasciciel zglosil, ze ma na farmie TRZY LISY, ktore nie odchodza. Blad
byl prawdziwy i moj:

    _fox_takes():  taken = min(taken, chickens.size() - 1)
                   if taken <= 0: return     <- nie emituje fox_visited

Sprite lisa znikal WYLACZNIE po sygnale `fox_visited` albo `fox_scared`.
Gdy stado bylo male (albo budzet strat wyczerpany), `taken` wychodzilo
zero, sygnal nie szedl i lis zostawal na wybiegu na zawsze. Kazde
kolejne przyjscie dokladalo nastepnego.

Dwie poprawki, zeby to sie nie powtorzylo przy zadnej przyszlej zmianie:
- Lis SAM pilnuje swojego czasu (`_process` odlicza `_life`) i odchodzi,
  nawet jesli zaden sygnal nie przyjdzie. Zycie sprite'a nie moze
  zalezec od cudzego sygnalu.
- Farma nie wpuszcza drugiego lisa, dopoki pierwszy jest na wybiegu.

Nowe zasady, wprost wedlug wlasciciela:

    LOSOWANIE   gra aktywna:    kostka raz na godzine realna, szansa 1/3
                gra nieaktywna: kostka raz na dobe, szansa 1/6
    WIZYTA      3 minuty realne, lis zabija po jednej kurze przez caly
                ten czas, az wybierze 30-60% stada
    PIERWSZA    ginie zaraz po wejsciu — lis ZAWSZE cos zabiera
    PALEC       20 trafien przegania lisa; po kazdym odskakuje gdzie
                indziej, wiec trzeba za nim nadazyc
    ODWET       przegoniony golymi rekami wraca 10 razy szybciej, chyba
                ze gospodarstwo ma psa albo plot — wtedy kara nie dziala
    OFFLINE     lis rozlicza sie od razu i odchodzi; gracz dostaje po
                powrocie informacje, ile kur zginelo (nie zastaje lisa)

PIES jest wreszcie WIDOCZNY. Dotad istnial tylko jako liczba w panelu —
wlasciciel kupil go i nie zobaczyl. Teraz siedzi przy kurniku, a gdy lis
wejdzie, rusza za nim i trzyma sie tuz za jego ogonem.

    kundel    200 zl  daje rade w 2 przypadkach na 3, goni ok. minuty
    owczarek  500 zl  daje rade zawsze, przegania w 3 sekundy

Pies nie zatrzymuje lisa przy bramie — skraca mu wizyte. Poniewaz lis
zabija stopniowo, kazda sekunda skrocenia to uratowana kura.

PLOT, nowa drabinka: 200/50%, 400/65%, 800/80%, 2000/95%.

CHOROBA: lek 20 zl zamiast 10. Nowe tempo — w grze aktywnej kolejna kura
choruje co minute realna, w nieaktywnej co cztery godziny. Chora sztuka
idzie do skupu za 5 zl zamiast darmowego uboju.

Odpowiedz na pytanie wlasciciela, czy da sie odroznic gre aktywna od
nieaktywnej: TAK, i bylo to mozliwe od poczatku. `Simulation.advance`
dostaje flage `offline`; nadrabianie czasu po powrocie woła ja z `true`,
a zwykla klatka z `false`. Teraz obie sciezki maja osobne liczby.

GRAFIKA: lis nizszy i wyrazniej podluzny (viewBox 230x104 zamiast
190x130), kica po wybiegu zamiast bujac sie w jednym miejscu jak kon na
biegunach. Plamy krwi przeniesione do warstwy `Decals` miedzy trawa
a zwierzetami i splaszczone w pionie — wczesniej lezaly nad wszystkim
i wygladaly, jakby unosily sie w powietrzu.

## WERSJA 12.0: plot i pies to dwie osobne rzeczy

Wlasciciel opisal to tak: pies do kupienia OD RAZU i TANSZY niz plot;
kundel goni lisa po dluzszej chwili i sporo kur ginie, lepszy pies za
500 goni od razu; pies kupiony raz zostaje; lis ZAWSZE cos zabija;
a zeby lis w ogole nie wszedl — od tego jest plot.

Przedtem byla jedna drabinka 0-5, w ktorej plot i pies robily to samo:
podbijaly szanse, ze lis zawroci przy bramie. Pies byl drugim szczeblem
za 1200 zl, wiec zeby go kupic, trzeba bylo najpierw postawic plot za
800 zl. Wlasciciel szukal psa w panelu i nie znalazl.

Teraz sa dwie niezalezne sciezki:

    PLOT  (buildings.guard)  czy lis w ogole wejdzie
      800 zl   60%
     1800 zl   80%
     4000 zl  100%

    PIES  (buildings.dog)    gdy juz wszedl: jak szybko wyleci i ile wezmie
      200 zl  kundel     5 s,  50% upatrzonego lupu
      500 zl  owczarek   2 s,  20% upatrzonego lupu

Pies nie zeruje strat — lis zawsze porywa co najmniej jedna kure.
Zero strat jest TYLKO wtedy, gdy gracz przegoni lisa palcem (trzy
trafienia). Dzieki temu pies ratuje gracza, ktory nie patrzy na ekran,
ale refleks nadal sie oplaca i jedyna mechanika reakcji w grze nie
umiera.

FORMAT ZAPISU 5 -> 6. Pole `guard_level` zmienia znaczenie, wiec stare
farmy sa przeliczane; nikt nie traci tego, za co zaplacil:

    stary poziom obrony -> plot, pies
      0 -> 0, 0        3 -> 2, 1
      1 -> 1, 0        4 -> 2, 2
      2 -> 1, 1        5 -> 3, 2

To pierwsza zmiana MAJOR wedlug zasady ustalonej dzien wczesniej:
pierwsza cyfra rosnie tylko przy zmianie formatu zapisu.

Przy okazji wyszedl blad w samych testach, ktory siedzial tam od dawna:
`GameData.balance()` zwraca WSPOLNY slownik, a pomocniki `_force_event`
i `_never_event` grzebia w nim na stale. Nowy test psa wyzerowal przez
to karencje lisa dla wszystkich testow uruchomionych pozniej. Doszly
`_snapshot_event` i `_restore_event`.

## Wersjonowanie — ustalone 2026-11-21

Numer: `MAJOR.MINOR`. MINOR rosnie przy kazdym wydaniu, MAJOR tylko przy
zmianie formatu zapisu (dzis `version: 5`) — to jedyna granica, ktora moze
kosztowac gracza farme.

Kazde wydanie dostaje **galaz** `vNUMER-krotki-opis`. Nie tagi, choc tagi
byly by wlasciwszym narzedziem: proxy w srodowisku Claude przepuszcza push
galezi, ale na tagu zwraca 403, przez API tez. Schemat, ktorego Claude nie
moze wykonac, jest nic nie wart.

Numer zyje dzis w trzech miejscach i trzeba je bumpowac razem:
- `core/util/game_data.gd` -> `const VERSION` (to czyta gra)
- `project.godot` -> `config/version` (zostal na 11.3, do wyrownania)
- `PROJECT_STATE.md` -> naglowek

Do zrobienia: `tools/release.sh NUMER "opis"`, ktory robi cala sekwencje
jedna komenda — bump wszystkich trzech miejsc, oba zestawy testow, build,
**sprawdzenie, czy w paczce jest prawdziwy adres Supabase, a nie atrapa**
(21.11 zlapane recznie, o wlos od wydania gry bez polaczenia z baza),
commit, galaz, push, gh-pages.

Cofanie sie do starszej wersji opisane dla wlasciciela w `WERSJE.md`.
Najwazniejsze: galaz `gh-pages` trzyma gotowa gre z kazdego wydania
osobno, wiec cofniecie strony nie wymaga budowania — wystarczy
`git reset --hard <skrot>` i `git push --force origin gh-pages`.

## ROZWIAZANIE zagadki "serwer nie odpowiada" (wersja 11.6)

Gra pokazala wlascicielowi dokladny powod bledu: **kod 8**. Sprawdzone
w samym silniku (`HTTPRequest` w Godot 4.7.2, nie z pamieci):

    RESULT_BODY_DECOMPRESS_FAILED = 8

To znaczy, ze zapytanie **doszlo do Supabase i wrocilo z odpowiedzia**,
a Godot nie potrafil rozpakowac ciala. Czyli: siec dziala, klucz dziala,
RLS pozwala czytac, farma jest na serwerze. Wszystkie wczesniejsze
hipotezy (RLS, CORS, Brave, uspiona baza, wyscig przy `cancel_request`)
byly chybione.

Dlaczego dotykalo tylko odczytu: zapis idzie z naglowkiem
`Prefer: return=minimal`, wiec serwer odsyla puste cialo — nie ma czego
rozpakowywac. Odczyt dostaje JSON spakowany gzipem i tam Godot sie
przewracal.

Poprawka w `services/cloud.gd`:
- `accept_gzip = false` na obu wezlach `HTTPRequest`. Rozpakowywanie
  zostawiamy przegladarce, ktora i tak to robi.
- `_body_text()` jako siatka bezpieczenstwa: jesli cialo mimo wszystko
  przyjdzie spakowane (pierwsze bajty 0x1f 0x8b), rozpakowujemy je sami.
- Kody 1, 7, 8 i 12 maja wreszcie nazwy po polsku. Kod 8 pokazywal sie
  jako "nieznany powod", przez co diagnostyka byla mniej warta.

Sprawdzone naprawde: atrapa serwera (`tools/mock_backend.py` z czwartym
argumentem `1`) pakuje teraz odpowiedzi gzipem tak jak Supabase.
Zbudowana gra w prawdziwym Chrome wczytala z niej farme po kodzie
(payload 4242 zl doszedl na ekran). Testy jednostkowe: `_test_body_unpacking`.

## Weryfikacja wersji 11.5 (wykonana w srodowisku Claude, Linux)

Wersja stabilizacyjna: zadnych zmian w balansie, tylko numer wersji na
ekranie i naprawiony test.

- `tests/tests.tscn`: **911 OK, 0 bledow**.
- `tests/smoke_ui.tscn`: **OK, trzy biegi pod rzad**.
- Baza Supabase sprawdzona ponownie o 17:47 UTC przez GitHub Actions:
  HTTP 200, 14 farm w tabeli, farmy 327733 i 756362 na miejscu.

Naprawiony blad w samym tescie dymnym: czekal na odejscie lisa przez
odliczanie KLATEK (`_frames(240)`), a animacja lisa trwa 2,7 sekundy
ZEGARKA. Na szybszym przebiegu 240 klatek mijalo w pol sekundy i test
oblewal sie na czyms, co w grze dziala poprawnie. Doszedl pomocnik
`_seconds(duration)`, ktory czeka czasem, nie klatkami.

Z tego wynika druga rzecz: test dymny trzeba odpalac z `--quit-after
30000`, nie `4000`. Stary limit 4000 klatek konczyl prace przed koncem
testu, co wygladalo jak przebieg bez wyniku.

## Co wiadomo o serwerze na 2026-11-21 (sprawdzone przez GitHub Actions)

Srodowisko Claude nie ma dostepu do `supabase.co` (DNS odrzucony przez
proxy), ale GitHub Actions ma. Przez recznie odpalone zadanie w repo
sprawdzone naprawde, nie z domyslu:

- `GET /rest/v1/saves?select=player_id&limit=1` z kluczem publikowalnym
  zwraca **HTTP 200** i wiersz. Baza zyje, tabela istnieje, RLS pozwala
  roli anon czytac. Hipoteza "RLS blokuje odczyty" jest ostatecznie
  obalona.
- W tabeli jest **14 farm**.
- Farma **327733** jest w bazie, ostatni zapis 2026-11-21 14:11:35 UTC.
- Farma **756362** jest w bazie, ostatni zapis 2026-11-21 14:09:03 UTC.

Wniosek: zapis dziala, serwer odpowiada, obie farmy wlasciciela sa cale.
Odczyt psuje sie dopiero w jego przegladarce. Wersja 11.4 pokazuje przy
nieudanym odczycie dokladny powod z `HTTPRequest.Result`, wiec nastepna
proba wlasciciela rozstrzygnie, co to jest.

## Weryfikacja wersji 11.4 (wykonana w srodowisku Claude, Linux)

Uruchomione naprawde, nie "powinno dzialac":

- `tests/tests.tscn` pod `--headless`: **911 testow OK, 0 bledow**.
  Doszly `_test_incubate_without_flock` (wyleg jaj po sprzedaniu calego
  stada rasy) i `_test_retry_same_code` (druga proba wczytania tego
  samego kodu po nieudanej pierwszej).
- `tests/smoke_ui.tscn` pod `xvfb-run` z `--rendering-driver opengl3`:
  **OK**. Doszly cztery sprawdzenia panelu inkubatora: procent na pasku,
  naglowek grupy, wiersz poziomu i to, czy pasek faktycznie rosnie.
- Zrzut ekranu panelu inkubatora obejrzany (`panel_inkubator_postep.png`):
  wiersz "Poziom 1 / 6", naglowek "W inkubatorze", pasek z napisem
  "25% - 3 min", kolumna liczb nie chowa sie juz pod paskiem przewijania.

Uwaga na przyszlosc: po zmianie `data/strings.csv` trzeba uruchomic
`godot --headless --path . --import`, zanim odpali sie testy. Bez tego
Godot czyta STARA skompilowana wersje tlumaczen i test moze przejsc na
nieaktualnym napisie — dokladnie to zdarzylo sie przy pierwszym
uruchomieniu w tej sesji (bledny format `DIAG_NO_ANSWER` przeszedl
niezauwazony).

## Weryfikacja wersji 11.3 (wykonana w srodowisku Claude, Linux)

- `tests/tests.tscn`: **902/902 OK**, w tym tlumaczenie kazdego kodu HTTP
  na podpowiedz.
- `tests/smoke_ui.tscn`: **OK**.
- Przy okazji znaleziony blad w samych testach: `_never_event` nie kasowal
  `hard_minutes`, wiec "wylaczony" lis i tak przychodzil po twardej
  gwarancji i psul pomiar produkcji jaj.
- **NIE sprawdzone:** prawdziwa baza wlasciciela. Proxy w srodowisku Claude
  dalej odrzuca `supabase.co` (sprawdzone ponownie: brak odpowiedzi).

## Weryfikacja wersji 11.2 (wykonana w srodowisku Claude, Linux)

- `tests/tests.tscn`: **892/892 OK**.
- `tests/smoke_ui.tscn`: **OK**, z nowym sprawdzeniem widocznosci odpowiedzi
  serwera w okienku.
- **NIE sprawdzone:** polaczenie z prawdziwym Supabase. Proxy w srodowisku
  Claude odrzuca `supabase.co`, wiec w tescie wychodzi "serwer nie odpowiada".
  Ktora z trzech odpowiedzi dostaje wlasciciel, moze powiedziec tylko on.

## Weryfikacja wersji 11.1 (wykonana w srodowisku Claude, Linux)

- `tests/tests.tscn`: **892/892 OK**.
- `tests/smoke_ui.tscn`: **OK**. Doszlo wpisywanie kodu klawiatura w grze:
  cyfry wchodza, kasowanie zabiera ostatnia, kod nie rosnie ponad szesc cyfr,
  a zatwierdzenie jest aktywne dopiero przy komplecie.
- Klawiatura sprawdzona takze w prawdziwym Chrome, klikaniem w przyciski.

## Weryfikacja wersji 11.0 (wykonana w srodowisku Claude, Linux)

- `tests/tests.tscn`: **892/892 OK**. Nowe: twarda gwarancja lisa i choroby
  mierzona na 20 przebiegach po 1200 minut, pelna obrona na 50 prob, droga
  rasa chorujaca czesciej od taniej, jednakowy czas w grze i poza nia.
- `tests/smoke_ui.tscn`: **OK**. Nowe: jedno dotkniecie zgarnia jajka
  z poblizu, a jajko poza promieniem zostaje na wybiegu.
- Uklad farmy i kolory przyciskow obejrzane na zrzutach.
- Straty nocne zmierzone osobno dla kazdego poziomu plotu.

## Weryfikacja wersji 10.4 (wykonana w srodowisku Claude, Linux)

- `tests/tests.tscn`: **887/887 OK**. Przepisany `_test_money_format`
  sprawdza, ze zadna kwota nie zawiera przecinka i ze jajko kazdej rasy ma
  widoczna wartosc w groszach.
- `tests/smoke_ui.tscn`: **OK**.
- Gorny pasek obejrzany na zrzucie przy wartosciach maksymalnych
  (1 500 000 zl, 98 765 jaj, 2 500 kg, 254+6/260 ptakow) — nic sie nie ucina.
- Przeplyw czasu zmierzony dwiema droga: pomiarem w prawdziwym Chrome oraz
  bezposrednio przez `Game.apply_gap` z wymuszonym brakiem aktywnosci okna.

## Weryfikacja wersji 10.3 (wykonana w srodowisku Claude, Linux)

- `tests/tests.tscn`: **864/864 OK**. Przepisany `_test_event_rules` mierzy
  teraz odstepy i gwarancje; doszlo `_test_starving_farm`.
- `tests/smoke_ui.tscn`: **OK**, trzy biegi pod rzad.
- `tools/balance_model.py` na 25 losowaniach: mediana **7,6 h** (zakres
  7,6-8,0). Rozrzut zmalal, bo lis stal sie przewidywalny, a plot go zawraca.

## Weryfikacja wersji 10.2 (wykonana w srodowisku Claude, Linux)

- `tests/tests.tscn`: **847/847 OK**. Doszlo `_test_event_rules`: karencja,
  prog stada, licznik czasu gry i **pomiar czestosci** obu zdarzen na 60
  przebiegach po godzinie — wynik musi trafic w srednia z balansu z dokladnoscia
  do 35%.
- `tests/smoke_ui.tscn`: **OK**. Doszlo sprawdzenie zawroconego lisa: pokazuje
  sie, nie da sie go stuknac, sam znika i nic nie zabiera.
- `tools/balance_model.py` na 25 losowaniach: mediana **12,6 h** przy graczu,
  ktory nigdy nie przegania lisa, i 12,2 h przy graczu przeganiajacym polowe
  wizyt. Jeden przebieg na 25 utknal — to cena losowania co minute przy lisie
  zabierajacym 30-90% stada przed kupnem plotu.

## Weryfikacja wersji 10.1 (wykonana w srodowisku Claude, Linux)

- `tests/tests.tscn`: **832/832 OK**. Doszly `_test_coop_limit` (pelny kurnik
  blokuje wyleg, nie zjada jaj, pisklę czeka i wchodzi po zwolnieniu miejsca)
  oraz pomiar plotu: na sto podejsc zawraca ponad siedemdziesiat, a przy
  braku plotu nie zawraca ani jednego.
- `tests/smoke_ui.tscn`: **OK**, trzy biegi pod rzad.
- Zrzut panelu sklepu obejrzany: suwak przewijania jest widoczny i gruby,
  licznik w pasku pokazuje 6/20.
- `tools/balance_model.py`: wygrana po 12,8 h.

## Weryfikacja wersji 10.0 (wykonana w srodowisku Claude, Linux)

- `tests/tests.tscn`: **818/818 OK**. Doszly `_test_roosters` (kury bez koguta
  nie znosza nic, sam kogut tez nie, kogut innej rasy nie pomaga, kupno
  i sprzedaz w sklepie, migracja starego zapisu) i `_test_lay_fairness`.
- `tests/smoke_ui.tscn` (xvfb): **OK**, cztery biegi pod rzad. Doszlo kupno
  koguta w sklepie i sprawdzenie, ze staje na wybiegu z wlasna grafika.
- Wersja przegladarkowa zbudowana i otwarta w prawdziwym Chrome: sklep
  pokazuje "Kup koguta", "Sprzedaj koguta" i "Zaszczep stado za 100 zl".
- `tools/balance_model.py`: wygrana po 13,6 h; przebieg przez wszystkie
  siedemnascie ras i wszystkie rozbudowy wypisany w konsoli.
- **NIE sprawdzone:** rozgrywka na telefonie wlasciciela i polaczenie
  z prawdziwym Supabase (proxy w srodowisku Claude odrzuca `supabase.co`).

## Weryfikacja wersji 9.0 (wykonana w srodowisku Claude, Linux)

- `tests/tests.tscn`: **797/797 OK**.
- `tests/smoke_ui.tscn` (xvfb, renderer programowy): **OK**, cztery biegi
  pod rzad bez bledu. Obejmuje ekran startowy, cztery panele budynkow,
  zbieranie jajka, sklep z siedemnastoma rasami (kazda z widocznym przyciskiem
  zakupu), inkubator, sprzedaz kury, okienko rasy, wczytanie farmy z kodu,
  zgnilozielone chore kury z mgielka, okienko "Uwaga, choroba!", wejscie lisa,
  piora, krew i plamy zostajace na wybiegu.
- Wersja przegladarkowa zbudowana i uruchomiona w prawdziwym Chrome
  (playwright-core): gra wstaje, ekran startowy dziala, sklep pokazuje
  wszystkie rasy az do Ayam Cemani za 8 000 zl, bez blokad.
- **NIE sprawdzone:** polaczenie z prawdziwym Supabase — proxy w srodowisku
  Claude odrzuca `supabase.co`, wiec chmura jest testowana tylko przeciwko
  atrapie (`tools/mock_backend.py`). Na zywym adresie musi to potwierdzic
  wlasciciel (napis "Serwer: polaczony" w Kurniku).

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
- Zdjecia ras: podmiana plikow w assets/photos/, bez zmian w kodzie.
- Z `POMYSLY.md` jeszcze nie zrobione: zamowienia od klientow, jakosc/genetyka
  pojedynczej kury, wahania cen na rynku, wystawy drobiu, pory roku.
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
- **Siedemnascie ras**, drabinka cen z rownym krokiem okolo 1,4x: 40, 55,
  80, 110, 150, 210, 290, 400, 550, 750, 1050, 1450, 2000, 2800, 4000,
  5600, 8000 zl.
- Gorna polka opiera sie na cenach swiatowych, nie polskich ogloszeniach:
  dorosly Ayam Cemani chodzi po 1200-3000 USD, a Dong Tao po 1000-2500 USD
  za pare. Srodek drabinki (Pavlovskaya ~86 USD, Orust ~100 USD, Totleger
  100-250 USD) tez pochodzi z cennikow hodowcow.
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
- Stan na wersje 8.0: pelna kolekcja ras po ~21,6 h gry, poltora miliona
  zlotych po ~23,2 h. Nowa rasa odblokowuje sie mniej wiecej co dwie godziny gry.
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

### Ceny i tempo (wersja 10.0)

- Rozbudowy sa duzo tansze niz w 9.0, bo wlasciciel nie kupowal ich w ogole.
  Kurnik: 40/500, 60/1400, 80/3200, 110/7000, 150/15000, 200/30000, 260/60000 —
  drabinka siega 260 ptakow, zeby przy siedemnastu rasach zmiescilo sie po
  kilka sztuk kazdej razem z kogutami. Magazyn ma piec poziomow, do worka
  2500 kg, inkubator piec, do 34 miejsc.
- **Trzy jaja na pisklę** zamiast szesciu (`incubator.eggs_per_chick`).
- Szczepienie: **stala setka za cale stado**, bez stawki od sztuki. Stawka
  rosla razem ze stadem i w praktyce nikt tego nie kupowal. Pole
  `vaccine_price_per_hen` zostaje w pliku balansu na wypadek powrotu do
  rozliczania od sztuki — teraz wynosi zero.
  **Uwaga na przyszlosc:** przy stalej setce choroba przestaje byc zagrozeniem
  dla kogos, kto pamieta o ponownym szczepieniu po kazdym wykluciu. Jesli ma
  gryzc, trzeba albo wprowadzic wygasanie szczepienia, albo wrocic do stawki
  od sztuki.
- Lis: co **15–36 minut** gry, zabiera 30–90% stada. Czesciej sie nie da.
  Model przy 6–18 minutach nie konczy gry nawet w 300 godzin, jesli gracz
  nie przegania lisa: stado zostaje na trzech kurach, bo odbudowa nie nadaza
  za strata 60% co kwadrans. Sprawdzone `SCARE_RATE` w `tools/balance_model.py`.
- Obrona przed lisem ma trzy poziomy: plot 600 (x1,7), pies 2500 (x3,0),
  pies i nocne swiatla 9000 (x5,0).
- Model calej gry: **wygrana po 13,6 h** (bylo 18,7 h w 9.0). Wlasciciel
  swiadomie zgodzil sie na szybsze tempo na czas testow.

### Sklep bez blokad (wersja 9.0)

- **Zadnych progow odblokowania.** Rasa ma jedna cene za sztuke, taka sama
  za pierwszym i za dziesiatym razem. Klucze `unlock` zniknely z
  `breeds.json`, `Simulation.check_unlocks()` zwraca pusta liste (zostawiona
  jako zaslepka, zeby nie przerabiac wszystkich wywolan), a
  `FarmState.is_unlocked()` zawsze zwraca `true`.
- Pole `unlocked_breeds` w zapisie **zostalo**, ale znaczy teraz co innego:
  "te rasy gracz kiedykolwiek mial". Sluzy wylacznie do tego, zeby okienko
  z historia rasy pokazalo sie raz, przy pierwszym zakupie. Format zapisu
  sie nie zmienil (`SaveGame.VERSION` dalej 4), wiec stare farmy wchodza bez
  konwersji.
- Powodem zmiany byla uwaga wlasciciela: prog "3 000 zl" czytal sie jak cena
  kury i wygladal jak absurdalny balans.
- **Hamulcem jest teraz czas odchowu.** `grow_seconds` kazdej rasy to czas
  bazowy przemnozony przez `(cena / 40) ^ 0,28`: leghorn 2,5 min, cemani
  32,5 min. Droga kura zarabia wiecej na jajku, ale dlugo nie pracuje.
- Sprzedaz dalej daje **70% ceny zakupu** — cemani kupiony za 8 000 zl wraca
  jako 5 600 zl, wiec rozmnozenie drogiej rasy ma sens.
- Wykladnik 0,28 nie jest zgadniety: `tools/balance_model.py` przeliczyl
  kilka wartosci i przy tej gra dochodzi do 1 500 000 zl w okolo **18,7 h**
  gry. Przy braku jakiegokolwiek hamulca wychodzilo 9,8 h.
- Druga wygrana (kolekcja wszystkich ras) jest **wylaczona**
  (`win.collection: false`): bez blokad dalo sie ja zrobic w 5,6 h i psula
  cel gry. Liczy sie tylko `win.money`.

### Okienko "nowa rasa odblokowana"

- `scenes/ui/panels/unlock_panel.tscn`: zlota ramka, obracajace sie promienie,
  iskry, portret rasy i kawalek jej historii z `BREED_*_LORE`.
- Odblokowania potrafia trafic sie po dwa naraz (gracz przekroczyl prog
  pieniedzy i liczbe kur w tej samej klatce), wiec rasy czekaja w kolejce
  i pokazuja sie jedna po drugiej.

### Kury i koguty (wersja 10.0)

- **Kura znosi jaja tylko wtedy, gdy na farmie jest kogut jej rasy.** Kogut
  sam nie znosi, je tyle samo co kura, zajmuje miejsce w kurniku i kosztuje
  tyle samo. Da sie go sprzedac na tych samych zasadach.
- Plec siedzi w `Chicken.is_rooster`; `Chicken.create_rooster()` to jedyny
  sposob, zeby ja ustawic. `FarmState` liczy osobno `laying_hen_count()`
  i `rooster_count()`, a `hen_count()` dalej znaczy **wszystkie ptaki** —
  tyle je paszy, tyle zajmuje miejsc i sposrod tylu wybiera lis.
- `hens_by_breed()` pomija koguty, bo sluzy do spisu niosek w kurniku
  i do liczb na kartach w sklepie. Koguty liczy `hens_of_breed(id, false, true)`.
- Pisklęta wykluwaja sie **zawsze jako kury**. Dzieki temu koguta kupuje sie
  raz na rase i gracz nie musi zgadywac, co mu sie wykluje.
- Ostrzezenia sa w trzech miejscach, bo cisza wygladalaby jak zepsuta gra:
  okienko `AlertPanel` przy kupnie pierwszej kury rasy bez koguta i przy
  sprzedazy ostatniego koguta, dopisek na karcie w sklepie i czerwony wpis
  w spisie stada w Kurniku.
- **Migracja zapisu (wersja 5).** Stare zapisy nie znaly kogutow, wiec po
  aktualizacji cale stado stanelo by w miejscu. `_migrate` dokleja jednego
  koguta do kazdej rasy, ktora gracz juz mial — zaszczepionego, jesli
  zaszczepione byly jego kury. Nowa farma dostaje koguta z `start.roosters`.
- Grafiki kogutow generuje `tools/gen_roosters.py` z jednego szablonu
  (wysoka sylwetka, duzy grzebien, sierpowy ogon) i palety na rase. Recznych
  poprawek w `assets/sprites/animals/rooster_*.svg` nie wprowadzac — zgina
  przy nastepnym przebiegu. Plotno 170x130, stopy na y=118, tak samo jak
  u kur, zeby `Sprite2D` z `offset = (4, -53)` postawil je na ziemi.

### Diagnoza polaczenia z serwerem (wersja 11.3)

- `Cloud` zapamietuje ostatnia rozmowe z serwerem: `last_action`,
  `last_http_code`, `last_result`, `last_rows`. `describe_last()` tlumaczy to
  na jedno zdanie, ktore mowi, CO naprawic — sam numer kodu nic nie daje.
- W Kurniku jest przycisk **"Sprawdz polaczenie z serwerem"**: jedno
  zapytanie i gotowa diagnoza pod spodem.
- Mapowanie kodow (pilnuje go `_test_server_diagnosis`):
  - 401/403 — RLS bez polityki dla roli `anon` albo zly klucz;
  - 404 — nie ma tabeli `saves`;
  - 409 — `player_id` bez warunku UNIQUE;
  - 200 i zero wierszy — albo farmy tam nie ma, albo RLS nie pozwala czytac;
  - brak odpowiedzi — siec albo zly adres projektu.
- **Najbardziej prawdopodobna przyczyna klopotow wlasciciela:** tabela `saves`
  ma wlaczone RLS bez polityk. Wtedy odczyt zwraca pusta liste (HTTP 200,
  zero wierszy), a zapis leci 401/403 — czyli dokladnie te dwa komunikaty
  na przemian, ktore zglosil. Klient wysyla wszystko poprawnie: oba naglowki
  z kluczem, `on_conflict=player_id` i `Prefer: resolution=merge-duplicates`.
- Potrzebny SQL (tabela + polityki) jest w `docs/supabase.sql`.
- **Uwaga na przyszlosc:** `updated_at` musi byc `bigint`, bo klient wysyla
  czas uniksowy jako liczbe. Kolumna `timestamptz` zalozona klikaniem w panelu
  Supabase odrzucilaby zapis z kodem 400.

### Komunikaty byly zaslaniane przez panele (wersja 11.2)

Wlasciciel zglosil: "wpisuje kod, klikam wczytaj i nic sie nie dzieje".
Gra odpowiadala za kazdym razem — tylko nie bylo tego widac.

- `Notice` (pasek z komunikatem) lezal w `hud.tscn` **przed** panelami, wiec
  kazde otwarte okno go zaslanialo: ekran powitalny, Kurnik, sklep. Gracz
  wpisywal kod, serwer odpowiadal "nie ma takiej farmy", a na wierzchu nie
  zmienialo sie nic.
- Pasek przeniesiony na **koniec listy dzieci** `Root`, czyli rysowany nad
  wszystkim. Ma `mouse_filter = IGNORE`, wiec niczego nie blokuje.
- Dodatkowo oba miejsca z kodem farmy — ekran powitalny i Kurnik — maja
  wlasna linijke na odpowiedz serwera, tuz pod przyciskiem. Po nacisnieciu
  pokazuje sie "Szukam farmy na serwerze…", a potem konkretna odpowiedz.
- Trzy mozliwe odpowiedzi i co znacza:
  - "farmy o takim kodzie u niego nie ma" — zapis nie dotarl na serwer;
  - "serwer nie odpowiada" — siec, tabela `saves` albo klucz;
  - "to kod tej farmy" — gracz wpisal kod farmy, na ktorej wlasnie jest.
- Test dymny sprawdza, ze po nacisnieciu wczytywania okienko od razu cos
  mowi i ze po odpowiedzi serwera dalej cos mowi.

### Klawiatura kodu rysowana w grze (wersja 11.1)

- Na telefonie **nie dalo sie wpisac kodu farmy**: klawiatura systemowa
  wpuszczala litery, ale nie cyfry. Pole `LineEdit` z
  `virtual_keyboard_type = KEYBOARD_TYPE_NUMBER` w eksporcie na przegladarke
  nie dostawalo cyfr z numerycznej klawiatury Androida.
- Zamiast walczyc z warstwa wejscia przegladarki, kod wpisuje sie wlasnymi
  przyciskami: `scenes/ui/panels/code_keypad.gd`. Zadna klawiatura systemowa
  nie bierze w tym udzialu, wiec dziala tak samo wszedzie.
- Uzywaja jej oba miejsca: ekran powitalny i panel Kurnika.
- Klawisz kasowania ma napis "Kasuj", a nie znak ⌫ — czcionka gry nie ma tego
  glifu i w przegladarce wychodzil pusty kwadrat. Sprawdzone zrzutem.
- Sprawdzone w prawdziwym Chrome klikaniem w przyciski, nie tylko w tescie
  dymnym: cyfry wchodza do pola.

### Jeden czas na wszystko (wersja 11.0)

- Dzielnik 60 dla nieaktywnej gry **zniknal**. Czas plynie tak samo, gdy
  gracz patrzy i gdy go nie ma: `offline.scale` = 1/3, czyli **trzy minuty
  zegara to jedna minuta gry**, a godzina zegara to 20 minut gry.
- Przeliczenie siedzi w `Game.apply_gap` i `Game._apply_elapsed`, wiec cala
  symulacja dostaje juz sekundy gry i nie musi o skali wiedziec. Jedyny
  wyjatek to progi zdarzen, ktore sa podane w minutach rzeczywistych.
- `offline.max_hours` 72 to dalej sufit na jedno nadrabianie, liczony
  w godzinach zegara (czyli 24 godziny gry).
- **Skutek uboczny, ktory trzeba znac:** noc poza gra przestala byc
  nieszkodliwa. Pomiar: osiem godzin nieobecnosci ze stadem 31 ptakow
  zostawia okolo 16 sztuk przy kazdym poziomie plotu ponizej 100% — tyle,
  ile wynosi sufit `hunger.offline_max_share` (0,5). Jesli ma byc lagodniej,
  to wlasnie ten parametr trzeba obnizyc.

### Lis: twarda gwarancja (wersja 11.0)

- Do krzywej narastania doszedl `hard_minutes`: po tylu **minutach
  rzeczywistych** bez lisa przychodzi on NA PEWNO, bez losowania. Lis 30,
  choroba 20.
- Wszystkie progi zdarzen (`grace_minutes`, `mean_minutes`, `hard_minutes`)
  sa teraz w minutach RZECZYWISTYCH, bo tak o nich mysli gracz. Przelicza je
  `Simulation._event_fires` przez `GameData.time_scale()`.
- Lis, ktory podszedl pod nieobecnosc gracza, **nie zabiera po cichu** —
  zostaje na wybiegu z wlasnym oknem na reakcje. Ten, ktory podszedl wczesniej
  w trakcie nadrabiania, rozlicza sie normalnie, ale ostatni czeka na powrot.
  Bez tego gracz dalej by lisa nie zobaczyl.
- Plot ma piec poziomow: 60%/800, 70%/1200, 80%/1800, 90%/2700, **100%/4000**.
  Ostatni wylacza lisa z gry calkowicie. Argumentowalem przeciw, wlasciciel
  zdecydowal inaczej; test pilnuje tej decyzji.
- Model przy graczu, ktory nigdy nie przegania lisa, **nie konczy gry**.
  Przy przeganianiu polowy wizyt: mediana 9,1 godziny gry (27 godzin zegara).
  Gwarantowany lis co pol godziny zabierajacy 30-90% stada wymaga albo
  reakcji, albo plotu — innej drogi nie ma.

### Wiekszy wybieg i zbieranie garsciami (wersja 11.0)

- Wybieg urosl z 420 na 550 px wysokosci. Kurnik i inkubator przesunely sie
  w gore (y 950 -> 800), drzewo ze srodka gornej czesci znikło, a pozostale
  drzewa i krzaki poszly wyzej. Zrodlem jest `RUN` w `tools/gen_ground.py` —
  grafika ziemi jest generowana, wiec `run.area` w balansie i piaskowy
  prostokat w `ground.svg` musza sie zgadzac.
- `max_visible_hens` 26 -> 36.
- Jedno dotkniecie zbiera **wszystkie jajka w promieniu** `run.pickup_radius`
  (300 px swiata, okolo 2 cm na telefonie). Przy znoszeniu co cztery sekundy
  zbieranie pojedynczo oznaczaloby setki stuknieć na minute.

### Chora kura i kolory przyciskow (wersja 11.0)

- Droga rasa choruje czesciej: waga losowania to **pierwiastek z ceny**.
  Sama cena dawalaby cemani dwiescie razy wieksza szanse niz leghornowi,
  czyli w praktyce chorowalyby wylacznie cemani.
- Kupno i sprzedaz roznia sie kolorem, bo na karcie rasy stoja jeden pod
  drugim: kupno ciemne zloto (`BuyButton`), sprzedaz blada zielen
  (`SellButton`), ubicie przygaszona czerwien (`CullButton`).
- Licznik kur w pasku pokazuje znowu **"33/60"**. Proba pokazania rezerwacji
  jako "33+27/60" byla nieczytelna; rezerwacja jest w panelu Kurnika.

### Kwoty bez przecinka i szerokosc licznikow (wersja 10.4)

- `NumberFormat.money` i `amount_only` podaja **pelne zlotowki**, zaokraglone
  w dol. Przecinek w liczniku na pasku nie miescil sie w polu i niczego nie
  wnosil. Zaokraglanie w dol, zeby licznik nigdy nie obiecal wiecej, niz
  gracz naprawde ma.
- `NumberFormat.small_money` jest do drobnych kwot: ponizej zlotowki podaje
  je w groszach ("40 gr"). Bez tego wartosc jajka pokazywalaby sie jako
  "0 zl" i rasy wygladalyby na bezwartosciowe. Uzywaja go karty ras
  w sklepie, spis stada i okienko nowej rasy.
- Gorny pasek: font licznikow 44 -> 34, ikona 64 -> 52 px, a cztery pola
  dziela szerokosc proporcjami (`size_flags_stretch_ratio`), bo najdluzsze
  napisy to "1 500 000" i "254+6/260". Sprawdzone zrzutem przy maksymalnych
  wartosciach — nic sie nie ucina.

### Jak plynie czas (zweryfikowane w wersji 10.4)

Wlasciciel zapytal wprost, wiec pomiar zamiast teorii.

- Symulacje prowadzi **zegar scienny**, nie delta klatki. Dopoki strona
  dostaje klatki, czas liczy sie w skali 1:1, nawet gdy przegladarka zwalnia
  petle gry.
- Gdy okno traci aktywnosc albo strona zostaje zamrozona (zminimalizowana
  przegladarka na telefonie), czas idzie sciezka offline:
  `real_seconds / offline.speed_divider`, czyli **60 razy wolniej**, i jest
  przyciety do `offline.max_hours` = 72 godzin zegara.
- Zmierzone: 1 min poza gra = 0 min gry, 10 min = 0,2 min, godzina = 1 min,
  noc (8 h) = 8 min, trzy doby i wiecej = 72 min (sufit).
- Prog `MAX_LIVE_STEP` = 30 s rozstrzyga, ktora sciezka: dziura dluzsza niz
  30 sekund jest rozliczana jak offline.
- **Uwaga na pomiary w Chrome bez okna:** headless nie dusi kart w tle tak,
  jak robi to telefon. W tescie playwright karta schowana za inna liczyla
  czas w pelnej skali. Na telefonie strona jest zamrazana naprawde, wiec
  obowiazuje dzielnik 60. Tego nie da sie sprawdzic w srodowisku Claude —
  moze to potwierdzic tylko wlasciciel na swoim telefonie.

### Narastajaca szansa na zdarzenie (wersja 10.3)

Stala szansa co minute nie dziala przy graniu z doskoku. Wlasciciel gra po
minucie, odklada telefon i wraca — i nie zobaczyl lisa przez trzy wersje
z rzedu, mimo ze liczby w balansie byly poprawne.

- Kazda minuta bez zdarzenia zwieksza szanse na nastepna. Krzywa:
  `p na minute = (t / G)^4`, gdzie `t` to minuty bez zdarzenia, a
  `G = mean_minutes * RAMP_SPAN` (1,95). Wykladnik 4 trzyma poczatek spokojny,
  a koniec stromy.
- Przy `mean_minutes` 45 daje to **srednia 45 minut i pewnosc po 84 minutach**;
  przy 15 — srednia 19 i pewnosc po 30. Wartosci wyliczone, nie zgadniete
  (skrypt liczacy rozklad jest w historii sesji; test pilnuje obu wlasnosci).
- Licznik suchych minut siedzi w `FarmState.event_dry` **i idzie do zapisu** —
  na tym polega narastanie miedzy sesjami. Stare zapisy zaczynaja od zera.
- Licznik stoi, dopoki furtka jest zamknieta (karencja, male stado). Inaczej
  gracz dostalby lisa w tej samej sekundzie, w ktorej stado urosło do piatej
  sztuki.
- Szanse na krok przelicza `1 - (1-p)^(step/60)`, a nie `p * step/60`.
  Mnozenie dawaloby przy p = 1 szanse 1/60 zamiast pewnosci, a pewnosc jest
  cala istota tej krzywej.
- `_test_event_rules` mierzy 20 przebiegow po 1200 minut i sprawdza dwie
  rzeczy: sredni odstep (lis 30-60 min, choroba 10-25) oraz **najdluzsza
  cisze**, ktora nie moze przekroczyc gwarancji.

### Slady po napasci (wersja 10.3)

- Lis zagryza na miejscu `fox.carcass_share` (polowe) lupu, a reszte wynosi.
  Wczesniej nie zostawialo po nim nic i gracz, ktory akurat nie patrzyl, nie
  mial skad wiedziec, co sie stalo.
- `hunger.corpse_seconds` 90 -> **300 s**, a plamy krwi (`fox.gd/SPLAT_SECONDS`)
  tyle samo. Zwloki i krew maja zostac na wybiegu na dlugo.

### Dziesieciokrotnie czestsze jaja (wersja 10.3)

- `egg_seconds` kazdej rasy podzielone przez 10: leghorn 4 s, cemani 13,6 s.
  Cel wlasciciela: zeby oplacalo sie sprzedawac jaja, a nie tylko kury, i zeby
  w hodowli blokerem byla pojemnosc inkubatora, a nie liczba jaj.
- **Pelny wybieg nie wstrzymuje juz znoszenia.** `run.max_eggs_on_ground` (40)
  ogranicza tylko to, ile jaj lezy naraz do zebrania palcem; nadmiar idzie
  prosto do magazynu. Bez tej zmiany dziesieciokrotne przyspieszenie nie
  daloby nic: cala produkcja byla ograniczona tempem stukania gracza.
- Zniklo przez to pole `Chicken.waiting_seconds` i cala kolejka sprawiedliwosci
  z 10.0 — nikt juz nie czeka na miejsce, wiec nie ma czego dzielic.
- Jedna kura moze w dlugim kroku zniesc wiecej niz jedno jajko (`while`,
  nie `if`): przy odstepie 4 s i kroku 10 s zdarza sie to stale.
- Skutek dla tempa gry: model spadl z 12,6 h do **7,6 h**. Mniej niz dwa razy
  szybciej, bo pasza i tak kosztuje od ptaka, a inkubator dalej ma tyle samo
  miejsc.

### Lis i choroba: zasady zdarzen (wersja 10.2)

Zasady podyktowane przez wlasciciela wprost, po tym jak przez caly wieczor
nie zobaczyl lisa ani razu. Pomiar przed zmiana: **0,8 wejscia na 30 minut
aktywnej gry** — a on gra krocej, wiec w praktyce nie widzial go nigdy.

- **Karencja:** przez pierwsze `grace_minutes` (30) gry od zalozenia farmy nie
  dzieje sie nic. Ani lis, ani choroba.
- **Prog stada:** przy mniej niz `min_hens` (5) ptakach tez nie dzieje sie nic.
- **Potem kostka co minute**, tak zeby zdarzenie wypadalo srednio raz na
  `mean_minutes`: lis 45 minut, choroba 15 minut. Odstepy sa przez to
  rozrzucone — czasem dwa pod rzad, czasem dluga cisza.
- Jedno miejsce decyduje o obu: `Simulation._event_fires(state, step, config)`.
- Czas gry liczy `FarmState.played_seconds()` z licznika dni, wiec karencja nie
  wymagala nowego pola w zapisie. **Uwaga:** dzien w grze trwa `day.seconds`,
  czyli dziesiec minut, wiec `state.days = 1` to dopiero dziesiec minut gry.
  Testy, ktore chca ominac karencje, ustawiaja `days = 10`.
- Choroba liczy sie teraz **na gospodarstwo, nie na kure**. Stawka od sztuki
  (`chance_per_hen_hour`) sprawiala, ze duze stado chorowalo bez przerwy,
  a male prawie wcale. Jedno losowanie to jedna chora kura.
- Pomiar po zmianie, 200 przebiegow: w pierwszych 30 minutach zero zdarzen,
  w godzinie gry 0,69 podejscia lisa i 1,96 zachorowania.
- `fox_timer` i `reset_fox_timer()` zniknely — nie ma juz odliczania. Stare
  zapisy moga miec klucz `fox_timer`, jest po prostu ignorowany.
- Testy wymuszaja zdarzenie przez `_force_event("fox")`, ktory podmienia
  `grace_minutes` i `mean_minutes` we wczytanej kopii balansu. Kazdy taki test
  konczy sie `GameData.reload()`.

### Chora kura: wyleczyc albo ubic (wersja 10.2)

- **Skup nie przyjmuje chorej sztuki.** `hen_sell_price(id, true)` zwraca zero,
  `sell_hen` szuka wylacznie zdrowych. Wczesniej chora szla pierwsza za ulamek
  ceny; `economy.sick_sell_share` zniknelo z balansu.
- Zostaja dwa wyjscia: lek (10 zl, bylo 80) albo `Game.cull_hen()` — ubicie
  **za darmo i bez zaplaty**, zeby ktos bez grosza przy duszy mogl zwolnic
  miejsce w kurniku.
- Przycisk uboju bierze najpierw kury, a koguta dopiero gdy to on jest chory —
  inaczej jedno nieuwazne stukniecie zostawialoby rase bez koguta.
- Szczepienie zdrozalo do 200 zl (bylo 100).

### Dziura znaleziona przez gracza: gra bez karmienia (wersja 10.3)

Znajomy wlasciciela zglosil: "jak zrobisz kury, to nie musisz ich karmic
nigdy". Pomiar potwierdzil dwie realne dziury:

- **Inkubator i odchow chodzily przy pustym magazynie.** Stado odnawialo sie
  szybciej, niz gloddzilo. Teraz bez paszy nic sie nie wykluwa i nic nie
  rosnie — sprawdza to `_test_starving_farm`.
- **Tempo padania nie zalezalo od wielkosci stada.** Jeden zgon na 50 sekund
  przy dwustu ptakach to godziny agonii. Teraz odstep dzieli sie przez
  `wielkosc stada / hunger.reference_hens` (10). Pomiar po poprawce: stado
  20 sztuk wymiera w 8 minut, 60 sztuk w 23, 150 sztuk w 33.
- Pusty magazyn melduje sie okienkiem (`ALERT_NO_FEED_*`), a nie znikajacym
  paskiem — zatrzymuje cale gospodarstwo, wiec zasluguje na przerwanie gry.

### Pasza (wersja 10.2)

- `feed_per_hen_minute` 0,085 -> **0,34** (cztery razy wiecej). Worek starczal
  na pol godziny i pasza w ogole nie byla problemem.
- Razem z tym spadla cena: worek 25 kg kosztuje 25 zl zamiast 60, a kazdy
  poziom magazynu daje tansze kilogramy (1,00 -> 0,75 zl/kg). Bez tego
  czterokrotne zuzycie zjadaloby caly zarobek i ekonomia staneleby.

### Obrona przed lisem: zawracanie, nie odwlekanie (wersja 10.1)

- Plot, pies i nocne swiatla **nie wydluzaja juz przerwy** miedzy wizytami.
  Zamiast tego przy kazdym podejsciu losuje sie, czy lis w ogole wejdzie:
  `FarmState.fox_block_chance()` to 0,90 / 0,97 / 0,99.
- Wlasciciel odrzucil poprzednia wersje wprost: plot za 600 zl, ktory wydluza
  przerwe 1,7 raza, jest w grze niezauwazalny. Zawracanie widac od razu.
- Zawrocony lis zglasza sie napisem (`HINT_FOX_BLOCKED`), inaczej gracz nie
  wie, za co zaplacil.
- Gorny prog to 0,99, a nie 0,995: `fox_block_chance` i tak przycina wyzsze
  wartosci, a przycisk pokazuje liczbe prosto z pliku i wyszloby klamliwe 100%.
  Pelnej nietykalnosci nie ma i byc nie powinno — pilnuje tego test.

### Pelny kurnik: widac go i blokuje wyleg (wersja 10.1)

- Licznik kur w gornym pasku pokazuje **"37/40"**, a nie samo "37". Przy
  dwoch wolnych miejscach robi sie pomaranczowy, przy zerze czerwony.
- Inkubator **odmawia** przyjecia jaj, gdy pisklę nie mialoby gdzie wyjsc.
  Wolne miejsce liczy sie razem z tym, co juz w drodze (`coop_free()` odejmuje
  jaja w inkubatorze i pisklęta na odchowie), inaczej dalo sie nabic kolejke,
  ktora stoi bez slowa wyjasnienia. Wyszarzony przycisk mowi, czego brakuje.
- Pisklę nigdy nie przepadalo — czekalo. Wlasciciel podejrzewal, ze znika,
  bo nic tego nie pokazywalo. Zachowanie zostaje, doszla informacja.

### Pasek przewijania (wersja 10.1)

- Domyslny suwak Godota jest cienki jak wlos; na telefonie przewijalo sie
  wylacznie przeciaganiem zawartosci i latwo bylo przypadkiem nacisnac
  przycisk pod palcem. `UiTheme._apply_scrollbar` daje tor i chwytliwy suwak
  o szerokosci `SCROLLBAR_WIDTH * 2` = 52 px widoku.

### Kolejka do znoszenia: kto dostaje miejsce na wybiegu

- Wybieg miesci `run.max_eggs_on_ground` jaj. Gdy jest pelny, wolne miejsce
  dostaje kura, ktora **najdluzej czeka z gotowym jajkiem** (`waiting_seconds`).
- Wczesniej decydowala kolejnosc w tablicy stada, czyli kolejnosc zakupu.
  Pomiar: 20 leghornow i po jednej cemani i araukanie, pol godziny, wybieg
  pelny — leghorny 292 jaja, araukana 1, cemani **0**. Po poprawce 161 / 6 / 7,
  czyli dokladnie rowny podzial miejsc miedzy wszystkie kury.
- Probowalem tez kursora przesuwanego o jeden na krok czasu. Nie dziala:
  rytm zbierania jaj przez gracza rezonuje z krokiem kursora (przy zbieraniu
  co 6 s kursor trafial tylko w co trzecia pozycje) i cemani dalej nie
  znosila nic. Licznik oczekiwania jest na to odporny.
- Pilnuje tego `_test_lay_fairness` w `tests/run_tests.gd`.

### Choroba i lis: oprawa (wersja 9.0)

- Choroba zdarza sie czesciej (`disease.chance_per_hen_hour` 0,45), lis
  przychodzi co **1–3 h** zamiast co kilka godzin. To one trzymaja balans
  zamiast progow w sklepie.
- Chora kura **nie ma juz ikonki apteczki**. Zamiast tego: zgnilozielony
  odcien (`SICK_TINT`), przechylenie sylwetki, osiadniecie na nogach,
  predkosc 11 px/s i mgielka z `CPUParticles2D` (`assets/ui/mist.svg`).
  Wszystko w `farm_chicken.gd`, przelaczane przez `set_sick()`.
- Pulapka, ktora juz raz ugryzla: `farm.gd/_flip_existing` przerzuca kure
  miedzy stanami **tylko w strone chorej**. Gdy dzialalo w obie strony,
  synchronizacja zdrowych cofala kury, ktore wlasnie zachorowaly, i gracz
  nigdy nie widzial zielonej kury.
- Choroba zglasza sie przez `Events.alert` i `AlertPanel`
  (`scenes/ui/panels/alert_panel.tscn`) — modalne okienko z kolejka, nie
  znikajacy pasek. Arkusz nie ma stalej wysokosci, tylko rosnie pod tresc.
- Lis: `class_name FarmFox` (bez tego `_nodes_of_type("Fox")` w tescie nic
  nie znajdowal), skala 1,45 i `z_index = 50`, zeby nie chowal sie za kurami.
  Przy wejsciu i ucieczce leci kurz, przy napasci: chmura piór, **krew**
  (`Blood`, `assets/ui/blood.svg`), szarpniecie calym wybiegiem i skok na kure.
- Plamy krwi (`assets/ui/blood_splat.svg`) zostaja na wybiegu przez 9 s.
  Siedza w **rodzicu** lisa, nie w nim samym — inaczej odjechalyby razem
  z uciekajacym lisem. Z tego samego powodu czastki maja `local_coords = false`.
- Komunikat przy wejsciu (`HINT_FOX_HERE`) jest podyktowany przez wlasciciela
  co do slowa: "Ojej, do twojego kurnika zakrada sie chytry lisek!".

### Test dymny: wspolrzedne dotkniecia

- `_tap` dostaje punkt we wspolrzednych **widoku** (1080x1920), ale
  `Input.parse_input_event` udaje zdarzenie z systemu, a system podaje
  piksele **okna**. Przy `window_width_override=486` okno jest 0,45 raza
  mniejsze, wiec bez przeliczenia przez `get_viewport().get_screen_transform()`
  dotkniecie ladowalo ponad dwa razy dalej niz cel i zaden budynek sie nie
  otwieral. Przeliczenie robi teraz samo `_tap`.
- Scena dokleja kury i jaja przy swoim cyklicznym odswiezeniu, a nie od razu
  po sygnale. Testy, ktore licza wezly, czekaja przez `_wait_for_nodes`
  zamiast zgadywac liczbe klatek — bez tego co trzeci bieg byl czerwony.

### Teksty: pulapka z cudzyslowami

- W `data/strings.csv` pole ujete w cudzyslowy konczy sie na pierwszym
  znaku `"`. Polski cudzyslow **zamykajacy** to `”`, nie `"` — uzycie
  prostego apostrofu w srodku opisu wciagnelo cztery kolejne klucze do
  opisu Ayam Cemani i gracz zobaczyl je jako gole nazwy.
- Pilnuje tego teraz `_test_strings`: kazdy klucz uzywany przez UI musi miec
  tlumaczenie, zadne pole nie moze zawierac nowej linii ani golego klucza.

### Zapis na serwerze (ETAP 6, wersja 8.0)

- `data/backend.json` wskazuje na projekt Supabase gracza. Klucz jest
  **publikowalny** (`sb_publishable_...`) — z zalozenia siedzi w aplikacji
  u gracza; klucza `sb_secret_...` nie wolno tam wpisywac.
- `services/cloud.gd` wysyla klucz w naglowkach `apikey` i `Authorization`,
  tak jak robi to biblioteka Supabase. Nowy format kluczy nie wymagal zmian
  w kodzie.
- **Gra dziala tak samo, gdy serwer nie odpowiada** — sprawdzone w Chrome
  z wylaczona atrapa: zapis leci do przegladarki, zero bledow na stronie.
- **Kod farmy to szesc cyfr** (100000-999999). Wczesniej byl dwunastoznakowy,
  literowo-cyfrowy — nie do zapamietania i zmudny do przepisania z telefonu.
  Stare kody nadal przyjmujemy przy wpisywaniu, zeby nikt nie stracil farmy;
  urzadzenie ze starym kodem dostaje nowy przy najblizszym uruchomieniu
  i nic przez to nie traci, bo lokalny zapis zostaje nietkniety.
- **Ekran powitalny** (`start_panel.tscn`) pokazuje sie tylko wtedy, gdy na
  urzadzeniu nie ma zadnego zapisu: krotko o grze, duzy przycisk "Nowa farma"
  i pole na kod istniejacej farmy. Po zalozeniu gospodarstwa drugi krok
  pokazuje swiezy kod — osobnym ekranem, bo to jedyna rzecz, ktora gracz
  musi sobie zapisac, a komunikat na pasku znika po kilku sekundach.
  Na czas ekranu `Game.pause_simulation(true)` wstrzymuje gospodarstwo.
- **Kod farmy** w kurniku: gracz moze przepisac kod z innego urzadzenia
  i przejac tamta farme. Przy takim przejeciu zapis z serwera wygrywa
  niezaleznie od tego, co lezy lokalnie (`_force_pull`) — inaczej swiezy
  zapis nowego telefonu przykrylby farme, po ktora gracz wlasnie siegnal.
- Test dymny przejmuje farme przez prawdziwy HTTP, ale **tylko przeciwko
  atrapie na localhost** — zeby nie pukac do bazy gracza.

### Zdjecia ras w sklepie

- Karta rasy pokazuje `assets/photos/<id>.jpg`, a gdy pliku nie ma — rysunek
  z wybiegu. Dzieki temu gra dziala bez zdjec. Lista nazw plikow i wymagania:
  `assets/photos/CZYTAJ_TO.md`.
