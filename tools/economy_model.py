#!/usr/bin/env python3
"""Model ekonomii z HODOWLA, a nie samymi jajkami.

Po co to jest
------------
`tools/upgrade_pacing.py` liczy tempo gry przy zalozeniu, ze gracz zyje
ze sprzedazy jaj. Tomek ustalil jednak inny zamysl:

    jajka to grosze na pasze, pieniadze robi sie na sprzedazy
    wyhodowanych drogich kur, a hamulcem jest czas rozrodu

Zanim obnizymy wartosc jajka, trzeba wiedziec, czy hodowla faktycznie
uniesie gre. Ten model liczy obie petle naraz i pozwala porownac warianty:

    python3 -I tools/economy_model.py              # dzisiejsze liczby
    python3 -I tools/economy_model.py --jajka 0.2  # jajka 5 razy tansze

Czego model NIE udaje: lisa, chorob, gry nieaktywnej, przerw gracza.
Sluzy do porownania TEMPA miedzy wariantami, nie do prognozy co do minuty.
"""

import argparse
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
BAL = json.loads((ROOT / "data" / "balance.json").read_text(encoding="utf-8"))
BREEDS = json.loads((ROOT / "data" / "breeds.json").read_text(encoding="utf-8"))
if isinstance(BREEDS, dict):
    BREEDS = BREEDS["breeds"]

SCALE = BAL["offline"]["scale"]
ECO = BAL["economy"]
EGGS_PER_CHICK = int(BAL.get("incubator", {}).get("eggs_per_chick", 3))


def real_hours(game_seconds: float) -> float:
    """Godziny przy zegarku z sekund gry."""
    return game_seconds / SCALE / 3600.0


def feed_per_hen_hour() -> float:
    # feed_per_hen_minute to kilogramy na MINUTE GRY. W godzine realna miesci
    # sie SCALE * 60 minut gry, bo gra chodzi trzy razy wolniej od zegarka.
    kg = float(ECO["feed_per_hen_minute"]) * SCALE * 60.0
    cena = float(ECO["feed_pack_price"]) / float(ECO["feed_pack_size"])
    return kg * cena


def coop_capacity(level: int) -> int:
    up = BAL["buildings"]["coop"]["upgrades"]
    if level <= 0:
        return int(BAL["buildings"]["coop"].get("capacity", 20))
    return int(up[min(level, len(up)) - 1].get("capacity", 20))


def coop_price(level: int) -> float:
    up = BAL["buildings"]["coop"]["upgrades"]
    if level >= len(up):
        return float("inf")
    return float(up[level]["price"])


def incubator_slots(level: int) -> int:
    inc = BAL["incubator"]
    up = inc.get("upgrades", [])
    if level <= 0:
        return int(inc.get("slots", 3))
    return int(up[min(level, len(up)) - 1].get("slots", 3))


def incubator_price(level: int) -> float:
    up = BAL["incubator"].get("upgrades", [])
    if level >= len(up):
        return float("inf")
    return float(up[level]["price"])


class Breed:
    def __init__(self, raw: dict, egg_factor: float):
        self.id = raw["id"]
        self.coop_level = int(raw.get("coop_level", 0))
        self.price = float(raw["price"])
        self.sell = float(raw["sell_price"])
        self.egg_value = float(raw["egg_value"]) * egg_factor
        self.egg_seconds = float(raw["egg_seconds"])
        self.cycle_h = real_hours(float(raw["incubate_seconds"]) + float(raw["grow_seconds"]))

    @property
    def eggs_per_hen_hour(self) -> float:
        return 3600.0 * SCALE / self.egg_seconds

    @property
    def egg_income_per_hen_hour(self) -> float:
        return self.eggs_per_hen_hour * self.egg_value

    @property
    def sale_income_per_slot_hour(self) -> float:
        """Zlotowki z jednego miejsca w inkubatorze na godzine realna."""
        return self.sell / self.cycle_h

    @property
    def eggs_per_slot_hour(self) -> float:
        return EGGS_PER_CHICK / self.cycle_h


def best_breed(breeds, coop_level: int) -> Breed:
    """Najdrozsza rasa, na ktora pozwala kurnik — to po niej gracz siega."""
    dostepne = [b for b in breeds if b.coop_level <= coop_level]
    return max(dostepne, key=lambda b: b.price)


def run(egg_factor: float, hours_cap: float = 400.0) -> list:
    breeds = [Breed(b, egg_factor) for b in BREEDS]
    feed = feed_per_hen_hour()

    money = float(BAL["start"].get("money", 150))
    coop, inc = 0, 0
    flock = len(BAL["start"].get("hens", [])) or 3
    kroki = []
    t = 0.0
    step = 0.05

    while t < hours_cap and (coop < len(BAL["buildings"]["coop"]["upgrades"])
                             or inc < len(BAL["incubator"].get("upgrades", []))):
        rasa = best_breed(breeds, coop)
        miejsca = coop_capacity(coop)
        stado = min(flock, miejsca)
        sloty = incubator_slots(inc)

        # Inkubator chodzi pelna para, o ile stado zniesie dosc jaj.
        jaja = stado * rasa.eggs_per_hen_hour
        potrzeba = sloty * rasa.eggs_per_slot_hour
        czynne = sloty if potrzeba <= jaja else (jaja / rasa.eggs_per_slot_hour if rasa.eggs_per_slot_hour else 0)
        zuzyte = czynne * rasa.eggs_per_slot_hour

        dochod = czynne * rasa.sale_income_per_slot_hour + (jaja - zuzyte) * rasa.egg_value
        koszt = stado * feed
        money += (dochod - koszt) * step
        t += step

        # Najpierw zapelnic kurnik, potem kupowac kolejne poziomy.
        if stado < miejsca and money >= rasa.price:
            money -= rasa.price
            flock += 1
            continue
        nastepny_kurnik = coop_price(coop)
        nastepny_inkub = incubator_price(inc)
        if nastepny_inkub <= nastepny_kurnik and money >= nastepny_inkub:
            money -= nastepny_inkub
            inc += 1
            kroki.append(("INKUBATOR %d (%d miejsc)" % (inc, incubator_slots(inc)), t, nastepny_inkub))
        elif money >= nastepny_kurnik:
            money -= nastepny_kurnik
            coop += 1
            kroki.append(("KURNIK %d (%d miejsc)" % (coop, coop_capacity(coop)), t, nastepny_kurnik))
    return kroki


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jajka", type=float, default=1.0,
                    help="mnoznik wartosci jajka, np. 0.2 = piec razy taniej")
    args = ap.parse_args()

    leghorn = Breed(next(b for b in BREEDS if b["id"] == "leghorn"), args.jajka)
    cemani = Breed(next(b for b in BREEDS if b["id"] == "cemani"), args.jajka)
    feed = feed_per_hen_hour()
    print("Zalozenia (mnoznik jajka: %.2f)" % args.jajka)
    print("  pasza                   %.1f zl na kure na godzine" % feed)
    print("  leghorn z jaj           %.1f zl/h na kure" % leghorn.egg_income_per_hen_hour)
    print("  leghorn z hodowli       %.0f zl/h na miejsce w inkubatorze" % leghorn.sale_income_per_slot_hour)
    print("  cemani z jaj            %.1f zl/h na kure" % cemani.egg_income_per_hen_hour)
    print("  cemani z hodowli        %.0f zl/h na miejsce w inkubatorze" % cemani.sale_income_per_slot_hour)
    stosunek = leghorn.egg_income_per_hen_hour / feed if feed else 0
    print("  jajka kontra pasza      jedna kura zarabia %.1f raza wiecej, niz zjada" % stosunek)
    print()
    print("%-28s %10s %12s" % ("zakup", "godzina", "cena"))
    print("-" * 54)
    for nazwa, godzina, cena in run(args.jajka):
        print("%-28s %8.1f h %10.0f zl" % (nazwa, godzina, cena))


if __name__ == "__main__":
    main()
