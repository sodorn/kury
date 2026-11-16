# PROJECT_STATE — Chicken Farm Simulator

Trwaly punkt odniesienia miedzy sesjami. Aktualizowany po kazdym etapie.

## Stan

- Aktualny etap: **ETAP 2 zakonczony** (wersja 0.2.0). Nastepny: ETAP 3.
- Silnik: Godot 4.7.2 stable (standard, GDScript), renderer Compatibility.
- Repo: `sodorn/kury`, galaz `main`. Claude pushuje, wlasciciel robi `git pull`.

## Decyzje (nie zmieniac bez powodu)

- 2D, portrait, viewport 1080x1920, stretch `canvas_items` + `keep_width`
  (szerokosc stala 1080, wysokosc rosnie na wyzszych ekranach).
- Swiat farmy 1080x2400, wysrodkowany w pionie; widok 3/4 z sortowaniem po Y,
  bez siatki izometrycznej.
- Logika gry w `core/` jako czyste klasy (RefCounted), bez wezlow i UI.
  Sceny tylko czytaja `Game.state` i sluchaja `Events`.
- Parametry gry wylacznie w `data/*.json`. Teksty w `data/strings.csv` (pl).
- Grafika wlasna (SVG, wektor), font Baloo 2 (licencja OFL, `assets/fonts/OFL.txt`).
- Dotyk: obiekty reaguja na `InputEventScreenTouch`; na PC mysz jest
  emulowana jako dotyk (ustawienie projektu).
- Zapis gry (od ETAPU 4): `user://save.json` z polem `version` i migracjami.
- Postep offline (od ETAPU 4): jedna funkcja `advance(state, dt)` dla ticka
  na zywo i nadrabiania; limit czasu offline w `balance.json`.

## Struktura

```
project.godot
data/        balance.json, buildings.json, strings.csv (+ wygenerowane .translation)
core/model/  farm_state.gd          stan gospodarstwa (czyste dane)
core/util/   number_format.gd
services/    config.gd, events.gd, game.gd   (autoloady: Config, Events, Game)
scenes/main/ main.tscn              scena startowa: Farm + Hud
scenes/farm/ farm.tscn/.gd, building.tscn/.gd
scenes/ui/   hud/ (pasek licznikow), panels/ (panel budynku), theme/ (UiTheme, SafeArea)
assets/      sprites/world, sprites/buildings, ui, fonts, icon.svg
tests/       run_tests.gd (logika, headless), smoke_ui.gd (okno + zrzuty)
tools/       gen_ground.py (generator tla i przedniego plotu)
```

## Wykonane

- ETAP 1: architektura, plan MVP, repo.
- ETAP 2: projekt Godot, scena farmy (tlo, wybieg, 4 budynki z `buildings.json`,
  drzewa, krzaki), HUD z licznikami (pieniadze, jaja, pasza, zwierzeta) czytanymi
  z `Game.state`, panel budynku otwierany dotknieciem, motyw UI, obsluga
  bezpiecznego obszaru ekranu.

## Weryfikacja ETAPU 2 (wykonana w srodowisku Claude, Linux)

- Import projektu w Godot 4.7.2: bez bledow.
- `tests/run_tests.gd`: 27/27 OK.
- `tests/smoke_ui.gd` (xvfb, renderer programowy) w 1080x1920 i 1080x2340:
  scena sie renderuje, dotkniecie kazdego z 4 budynkow otwiera panel z poprawnym
  tytulem, dotkniecie tla zamyka panel.
- NIE sprawdzone: uruchomienie na Windows, na telefonie, wydajnosc, bezpieczny
  obszar na realnym urzadzeniu.

## Nastepne zadania (ETAP 3)

- Model kury i ras (`data/breeds.json`), kury chodzace po wybiegu (sortowanie Y).
- Produkcja jaj wg configu, zuzycie paszy, zbieranie dotknieciem, animacja zbioru.
- Sprzedaz jaj w sklepie; panel budynku z realnymi akcjami zamiast notki.
- `core/simulation.gd` z `advance(state, dt)` + testy.

## Znane problemy / uwagi

- Liczniki HUD mieszcza ok. 6 cyfr; skracanie duzych liczb (1,2 mln) w ETAPIE 5.
- Eksport Android (ETAP 7): potwierdzic, ze `data/*.json` trafiaja do paczki
  (w razie potrzeby filtr `*.json` w presecie eksportu); potwierdzic wersje
  Android SDK wymagane przez Godot 4.7.
- Srodowisko Claude nie ma dostepu do Android SDK: APK buduje wlasciciel.
- Ikona aplikacji (`assets/icon.svg`) jest robocza.

## Komendy

```
godot --headless --path . --import
godot --headless --path . -s tests/run_tests.gd
godot --path . -s tests/smoke_ui.gd -- <katalog_na_zrzuty>
python3 tools/gen_ground.py
```
