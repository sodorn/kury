# PROJECT_STATE — Chicken Farm Simulator

Trwaly punkt odniesienia miedzy sesjami. Aktualizowany po kazdym etapie.

## Stan

- Aktualny etap: **ETAP 2 zakonczony**. Nastepny: ETAP 3.
- Wersje grafiki: **1.0** plaski wektor (galaz `v1.0-grafika-plaska`, commit 6ea3a3c),
  **2.1** pastelowa, miekkie kontury, zaokraglone sylwetki (galaz `main`) — aktualna.
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
```

## Wykonane

- ETAP 1: architektura, plan MVP, repo.
- ETAP 2: projekt Godot, scena farmy (tlo, wybieg, 4 budynki, drzewa, krzaki),
  HUD z licznikami czytanymi z `Game.state`, panel budynku otwierany dotknieciem,
  motyw UI, obsluga bezpiecznego obszaru ekranu.
- ETAP 2 (poprawki po pierwszym uruchomieniu u wlasciciela):
  budynki przeniesione z kodu do sceny (wczesniej `farm.tscn` wygladala w
  edytorze na pusta lake); `Config` zastapiony przez `GameData`; obszary dotyku
  zapisane w scenie (znikly ostrzezenia przy wezlach `Shape`); testy przerobione
  ze skryptow `-s` na sceny.

## Weryfikacja ETAPU 2 (wykonana w srodowisku Claude, Linux)

- Import projektu w Godot 4.7.2: bez bledow.
- `tests/tests.tscn`: 36/36 OK (w tym: kazdy budynek z `buildings.json` jest
  w scenie farmy, ma grafike i wpis w danych).
- `tests/smoke_ui.tscn` (xvfb, renderer programowy) w 1080x1920 i 1080x2340:
  scena sie renderuje, dotkniecie kazdego z 4 budynkow otwiera panel z poprawnym
  tytulem, dotkniecie tla zamyka panel.
- Edytor uruchomiony na farm.tscn: brak ostrzezen przy wezlach.
- NIE sprawdzone: uruchomienie na Windows, na telefonie, wydajnosc, bezpieczny
  obszar na realnym urzadzeniu.

## Nastepne zadania (ETAP 3)

- Model kury i ras (`data/breeds.json`), kury chodzace po wybiegu (sortowanie Y).
- Produkcja jaj wg configu, zuzycie paszy, zbieranie dotknieciem, animacja zbioru.
- Sprzedaz jaj w sklepie; panel budynku z realnymi akcjami zamiast notki.
- `core/simulation.gd` z `advance(state, dt)` + testy.

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
