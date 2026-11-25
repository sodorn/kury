# Chicken Farm Simulator

Gra 2D na Androida (Godot 4.7.2 stable, wersja standard — nie .NET).
Stan prac, architektura i decyzje: [PROJECT_STATE.md](PROJECT_STATE.md).

## Jak uruchomic gre na PC

1. `git pull`
2. Uruchom Godota, kliknij **Import** i wskaz plik `project.godot` z tego katalogu.
3. Poczekaj, az pasek na dole skonczy importowac zasoby (pierwszy raz trwa chwile).
4. Wcisnij **F5**.

To, co widac w oknie edytora, nie jest gra — gre widac dopiero po F5.
Mysz dziala w grze tak jak palec na telefonie.

## Jak otworzyc mape fermy w edytorze

W panelu po lewej: `scenes` > `farm` > `farm.tscn` (dwuklik).
Zakladka **2D** u gory pokazuje cala ferme: budynki, wybieg, drzewa.
Klawisz `F` wysrodkowuje widok na zaznaczonym obiekcie.

## Testy

```
godot --headless --path . res://tests/tests.tscn        # logika i dane
godot --path . res://tests/smoke_ui.tscn -- <katalog>   # klikanie + zrzuty
```
