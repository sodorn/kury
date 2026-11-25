#!/usr/bin/env python3
"""Ile realnego czasu zajmuje dojscie do kolejnych poziomow rozbudowy.

Model jest celowo prosty, ale karmiony PRAWDZIWYMI liczbami z
`data/balance.json` i `data/breeds.json`. Gracz:

  - trzyma kurnik pelny najtanszej oplacalnej rasy,
  - zbiera i sprzedaje jaja (to dzis glowny dochod),
  - placi za pasze wedlug biezacego poziomu magazynu,
  - kupuje po kolei: brakujace kury, potem najtanszy sensowny upgrade.

Czego model NIE udaje: lisa, chorob, hodowli na sprzedaz i gry nieaktywnej.
Sluzy do jednego — porownania TEMPA miedzy poziomami, a nie do prognozy
co do minuty.

Uruchomienie:  python3 -I tools/upgrade_pacing.py
"""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
import sys
sys.path.insert(0, str(ROOT / "tools"))
import dane  # noqa: E402
BAL = dane.load_balance()
BREEDS = json.loads((ROOT / "data" / "breeds.json").read_text(encoding="utf-8"))

SCALE = BAL["offline"]["scale"]          # ile czasu gry mija na sekunde realna
ECO = BAL["economy"]


def real_hours(game_seconds: float) -> float:
    return game_seconds / SCALE / 3600.0


def egg_income_per_hen_hour(breed: dict) -> float:
    """Zlotowki z jaj jednej kury na godzine REALNA."""
    per_game_second = float(breed["egg_value"]) / float(breed["egg_seconds"])
    return per_game_second * SCALE * 3600.0


def feed_cost_per_hen_hour(storage_level: int) -> float:
    """Koszt paszy jednej kury na godzine realna przy danym magazynie."""
    per_kg = min(float(o["per_kg"]) for o in ECO["feed_options"])  # big-bag, magazyn bez znaczenia
    kg_per_game_minute = float(ECO["feed_per_hen_minute"])
    kg_per_real_hour = kg_per_game_minute * (60.0 * SCALE)
    return kg_per_real_hour * per_kg


def coop_capacity(level: int) -> int:
    base = int(BAL["buildings"]["coop"]["capacity"])
    ups = BAL["buildings"]["coop"]["upgrades"]
    return base if level <= 0 else int(ups[min(level, len(ups)) - 1]["capacity"])


def simulate(breed_id: str = "leghorn", hours_cap: float = 400.0) -> list:
    """Zwraca liste zdarzen: (godzina realna, co kupiono, stan kasy)."""
    breed = next(b for b in BREEDS if b["id"] == breed_id)
    hen_price = float(breed["price"])
    income = egg_income_per_hen_hour(breed)

    money = float(BAL["start"]["money"])
    hens = len(BAL["start"]["hens"])
    coop_lvl = storage_lvl = 0
    t = 0.0
    events = []
    coop_ups = BAL["buildings"]["coop"]["upgrades"]
    store_ups = BAL["buildings"]["storage"]["upgrades"]

    while t < hours_cap:
        net_per_hour = hens * (income - feed_cost_per_hen_hour(storage_lvl))
        if net_per_hour <= 0:
            break

        # Co kupujemy najblizej: kure, rozbudowe kurnika albo magazynu.
        wanted = []
        if hens < coop_capacity(coop_lvl):
            wanted.append((hen_price, "kura"))
        if coop_lvl < len(coop_ups):
            wanted.append((float(coop_ups[coop_lvl]["price"]), "kurnik"))
        if storage_lvl < len(store_ups):
            wanted.append((float(store_ups[storage_lvl]["price"]), "magazyn"))
        if not wanted:
            break
        # Pelny kurnik ma pierwszenstwo: kury to zrodlo dochodu.
        wanted.sort(key=lambda x: (x[1] != "kura", x[0]))
        price, what = wanted[0]

        if money < price:
            wait = (price - money) / net_per_hour
            t += wait
            money += wait * net_per_hour
            if t >= hours_cap:
                break
        money -= price
        if what == "kura":
            hens += 1
        elif what == "kurnik":
            coop_lvl += 1
            events.append((t, "KURNIK %d (%d miejsc)" % (coop_lvl, coop_capacity(coop_lvl)), price))
        else:
            storage_lvl += 1
            events.append((t, "MAGAZYN %d" % storage_lvl, price))
    return events


def main() -> None:
    breed = next(b for b in BREEDS if b["id"] == "leghorn")
    print("Zalozenia modelu")
    print("  skala czasu          1 sekunda realna = %.3f sekundy gry" % SCALE)
    print("  leghorn z jaj        %.0f zl na godzine realna" % egg_income_per_hen_hour(breed))
    print("  pasza (magazyn 0)    %.1f zl na kure na godzine" % feed_cost_per_hen_hour(0))
    print("  pasza (magazyn max)  %.1f zl na kure na godzine"
          % feed_cost_per_hen_hour(len(BAL["buildings"]["storage"]["upgrades"])))
    print()
    print("%-26s %10s %12s %10s" % ("zakup", "godzina", "cena", "odstep"))
    print("-" * 62)
    last = 0.0
    for t, what, price in simulate():
        print("%-26s %9.1f h %11s zl %8.1f h" % (what, t, "%.0f" % price, t - last))
        last = t
    print()
    print("Czas do pelnej rozbudowy: %.1f godzin realnej, aktywnej gry" % last)


if __name__ == "__main__":
    main()
