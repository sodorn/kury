#!/usr/bin/env python3
"""Model ekonomii gry — sprawdza, czy liczby z data/*.json trzymaja sie kupy.

Uruchomienie z katalogu projektu:  python3 tools/balance_model.py

Czesc 1: tabela oplacalnosci kazdej rasy (zwrot z jaj, zysk z hodowli).
Czesc 2: symulacja gracza, ktory gra rozsadnie - karmi stado, sprzedaje jaja,
trzyma tyle kur najlepszej rasy, by inkubator chodzil pelny, sprzedaje
nadwyzke mlodych, rozbudowuje inkubator i kupuje kazda nowa rase, gdy sie
odblokuje. Wypisuje, po ilu godzinach dochodzi do wygranej.

Nie zastepuje grania, ale wylapuje liczby bez sensu: rase, ktora nigdy sie
nie zwraca, albo milion osiagalny w kwadrans.
"""
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BREEDS = {b["id"]: b for b in json.loads((ROOT / "data/breeds.json").read_text())}
BALANCE = json.loads((ROOT / "data/balance.json").read_text())

STEP = 1.0  # sekunda
MAX_HOURS = 300


def feed_cost_per_unit() -> float:
    economy = BALANCE["economy"]
    return economy["feed_pack_price"] / economy["feed_pack_size"]


def profit_per_hen_minute(breed_id: str) -> float:
    """Zysk z jednej kury na minute: jaja minus pasza."""
    breed = BREEDS[breed_id]
    eggs_per_minute = 60.0 / breed["egg_seconds"]
    feed = BALANCE["economy"]["feed_per_hen_minute"] * feed_cost_per_unit()
    return eggs_per_minute * breed["egg_value"] - feed


def payback_minutes(breed_id: str) -> float:
    """Po ilu minutach kura zwraca swoja cene z samych jaj."""
    profit = profit_per_hen_minute(breed_id)
    if profit <= 0:
        return float("inf")
    return BREEDS[breed_id]["price"] / profit


def cycle_seconds(breed_id: str) -> float:
    breed = BREEDS[breed_id]
    return breed["incubate_seconds"] + breed["grow_seconds"]


def breeding_profit_per_hour(breed_id: str, slots: int) -> float:
    """Zysk z odchowywania i sprzedazy mlodych tej rasy, na godzine."""
    breed = BREEDS[breed_id]
    eggs_used = BALANCE["incubator"]["eggs_per_chick"]
    revenue = breed["sell_price"] - eggs_used * breed["egg_value"]
    return revenue * slots * 3600.0 / cycle_seconds(breed_id)


def hens_to_saturate(breed_id: str, slots: int) -> int:
    """Ile kur danej rasy trzeba, by inkubator nie stal pusty."""
    per_chick = BALANCE["incubator"]["eggs_per_chick"]
    needed = slots * per_chick * BREEDS[breed_id]["egg_seconds"] / cycle_seconds(breed_id)
    return max(3, int(needed) + 1)


## Jaka czesc wizyt lisa gracz przegania, zanim porwie kury.
SCARE_RATE = 0.0


def simulate(verbose: bool = True) -> dict:
    money = float(BALANCE["start"]["money"])
    feed = float(BALANCE["start"]["feed"])
    hens: dict[str, int] = {}
    for breed_id in BALANCE["start"]["hens"]:
        hens[breed_id] = hens.get(breed_id, 0) + 1
    owned_ever = set(hens)
    unlocked = {b for b, d in BREEDS.items() if not d.get("unlock")}
    incubating: list[list] = []
    growing: list[list] = []
    eggs: dict[str, int] = {}
    timers = {b: 0.0 for b in BREEDS}

    day_seconds = BALANCE["day"]["seconds"]
    slots = BALANCE["incubator"]["slots"]
    upgrades = list(BALANCE["incubator"].get("upgrades", []))
    per_chick = BALANCE["incubator"]["eggs_per_chick"]
    feed_rate = BALANCE["economy"]["feed_per_hen_minute"]
    pack_size = BALANCE["economy"]["feed_pack_size"]
    pack_price = BALANCE["economy"]["feed_pack_price"]
    goal = BALANCE["win"]["money"]
    disease = BALANCE["disease"]
    fox = BALANCE["fox"]
    vaccine_per_hen = disease["vaccine_price_per_hen"]
    vaccine_flat = disease["vaccine_price"]
    # Kazda rasa, ktora gracz trzyma, potrzebuje jednego koguta. Kogut
    # kosztuje tyle co kura, je tyle co kura i zajmuje miejsce w kurniku,
    # ale nie znosi — to staly podatek od wejscia w nowa rase.
    roosters: dict[str, int] = {}
    for breed_id in BALANCE["start"].get("roosters", []):
        roosters[breed_id] = roosters.get(breed_id, 0) + 1
    vaccinated = 0
    fox_share = (fox["min_share"] + fox["max_share"]) / 2
    fox_visits = 0
    vaccine_spent = 0.0
    buildings = BALANCE["buildings"]
    coop_up = list(buildings["coop"]["upgrades"])
    store_up = list(buildings["storage"]["upgrades"])
    guard_up = list(buildings["guard"]["upgrades"])
    capacity = buildings["coop"]["capacity"]
    guard_block = 0.0
    fox_dry = 0.0
    SCALE = BALANCE["offline"]["scale"]

    history = []
    starved = 0
    seconds = 0.0
    while seconds < MAX_HOURS * 3600:
        seconds += STEP
        day = int(seconds / day_seconds)
        total_hens = sum(hens.values())
        total_birds = total_hens + sum(roosters.values())
        best = max((b for b in hens if hens[b] > 0),
                   key=lambda b: BREEDS[b]["sell_price"], default=None)

        # --- rozbudowa budynkow ------------------------------------------
        # Gracz doklada budynek, gdy stac go z zapasem. Kurnik ma
        # pierwszenstwo, bo bez miejsca stado nie urosnie.
        crowded = total_birds + len(growing) >= capacity - 2
        while coop_up and crowded and money >= coop_up[0]["price"] * 2:
            up = coop_up.pop(0)
            money -= up["price"]
            capacity = up["capacity"]
            history.append((seconds / 3600.0, "kurnik na %d kur" % capacity))
        # Plot kupuje sie od razu, jak tylko stac: lis jest najwiekszym
        # zagrozeniem dla stada, a 600 zl to najtansza rozbudowa w grze.
        while guard_up and money >= guard_up[0]["price"] * 1.3:
            up = guard_up.pop(0)
            money -= up["price"]
            guard_block = up["block_chance"]
            history.append((seconds / 3600.0,
                            "obrona przed lisem: zawraca %d%% podejsc" % round(guard_block * 100)))
        while store_up and money >= store_up[0]["price"] * 3:
            up = store_up.pop(0)
            money -= up["price"]
            pack_size, pack_price = up["pack_size"], up["pack_price"]
            history.append((seconds / 3600.0, "magazyn: worek %d kg" % pack_size))

        # --- pasza -------------------------------------------------------
        need = total_birds * feed_rate * 15  # zapas na 15 minut
        while feed < need and money >= pack_price:
            money -= pack_price
            feed += pack_size
        burn = total_birds * feed_rate * STEP / 60.0
        if feed >= burn:
            feed -= burn
        else:
            feed = 0.0
            starved += 1
            continue  # glodne kury nie znosza

        # --- znoszenie jaj ----------------------------------------------
        for breed_id, count in hens.items():
            if count == 0 or roosters.get(breed_id, 0) == 0:
                continue
            timers[breed_id] += STEP * count
            interval = BREEDS[breed_id]["egg_seconds"]
            while timers[breed_id] >= interval:
                timers[breed_id] -= interval
                eggs[breed_id] = eggs.get(breed_id, 0) + 1

        # --- inkubator ---------------------------------------------------
        occupied = total_birds
        for breed_id in sorted(hens, key=lambda b: -BREEDS[b]["sell_price"]):
            while (len(incubating) + len(growing) < slots
                   and occupied < capacity
                   and eggs.get(breed_id, 0) >= per_chick and hens[breed_id] > 0):
                occupied += 1
                eggs[breed_id] -= per_chick
                incubating.append([breed_id, BREEDS[breed_id]["incubate_seconds"]])
        for batch in list(incubating):
            batch[1] -= STEP
            if batch[1] <= 0:
                incubating.remove(batch)
                growing.append([batch[0], BREEDS[batch[0]]["grow_seconds"]])
        for chick in list(growing):
            chick[1] -= STEP
            if chick[1] <= 0:
                growing.remove(chick)
                hens[chick[0]] = hens.get(chick[0], 0) + 1

        # --- sprzedaz jaj: zapas tylko dla najlepszej rasy ---------------
        for breed_id, count in list(eggs.items()):
            reserve = slots * per_chick if breed_id == best else 0
            surplus = count - reserve
            if surplus > 0:
                money += surplus * BREEDS[breed_id]["egg_value"]
                eggs[breed_id] = reserve

        # --- sprzedaz nadwyzki kur --------------------------------------
        for breed_id in list(hens):
            if breed_id == best:
                keep = hens_to_saturate(breed_id, slots)
            else:
                keep = 1  # jedna zostaje do kolekcji
            while hens[breed_id] > keep:
                hens[breed_id] -= 1
                money += BREEDS[breed_id]["sell_price"]

        # --- szczepienie nowych kur w stadzie ----------------------------
        # Model zaklada gracza, ktory szczepi to, co zatrzymuje. Kury
        # odchowane na sprzedaz ida dalej od razu, wiec ich nie szczepi.
        if total_birds > vaccinated and money > vaccine_flat + vaccine_per_hen * (total_hens - vaccinated):
            cost = vaccine_flat + vaccine_per_hen * (total_birds - vaccinated)
            money -= cost
            vaccine_spent += cost
            vaccinated = total_birds
        vaccinated = min(vaccinated, total_birds)

        # --- lis ---------------------------------------------------------
        # Lis: cisza przez pierwsze grace_minutes gry i przy malym stadzie,
        # potem losowanie proporcjonalne do dlugosci kroku.
        # Krzywa i twardy sufit z Simulation._event_fires. Progi w balansie sa
        # w minutach rzeczywistych, a model liczy w sekundach gry — stad SCALE.
        grace_game = fox["grace_minutes"] * 60 * SCALE
        if seconds >= grace_game:
            fox_dry += STEP
        dry_real = fox_dry / 60.0 / SCALE
        span = fox["mean_minutes"] * 1.95
        chance = min(dry_real / span, 1.0) ** 4
        hard_hit = fox.get("hard_minutes", 0) > 0 and dry_real >= fox["hard_minutes"]
        if seconds >= grace_game and (hard_hit
                or random.random() < 1.0 - (1.0 - chance) ** (STEP / 60.0 / SCALE)):
            fox_dry = 0.0
            if random.random() < guard_block:
                # Plot, pies albo swiatla zawrocily lisa od zagrody.
                pass
            elif random.random() < SCARE_RATE:
                # Gracz patrzacy na ekran zdazy w lisa stuknac trzy razy.
                pass
            elif total_birds >= fox["min_hens"]:
                taken = max(1, min(int(round(total_birds * fox_share)), total_hens - 1))
                fox_visits += 1
                left = taken
                for breed_id in sorted(hens, key=lambda b: BREEDS[b]["sell_price"]):
                    while left > 0 and hens[breed_id] > 0:
                        hens[breed_id] -= 1
                        left -= 1
                vaccinated = max(0, vaccinated - taken)

        # --- rozbudowa inkubatora ---------------------------------------
        while upgrades and money >= upgrades[0]["price"] * 2:
            upgrade = upgrades.pop(0)
            money -= upgrade["price"]
            slots = upgrade["slots"]
            history.append((seconds / 3600.0, "inkubator na %d jaj" % slots))

        # --- odblokowania i zakup nowej rasy ----------------------------
        for breed_id, breed in BREEDS.items():
            if breed_id in unlocked:
                continue
            need_unlock = breed.get("unlock", {})
            if (money >= need_unlock.get("money", 0)
                    and day >= need_unlock.get("days", 0)
                    and total_hens >= need_unlock.get("hens", 0)
                    and feed >= need_unlock.get("feed", 0)
                    and all(hens.get(r, 0) > 0 for r in need_unlock.get("breeds", []))):
                unlocked.add(breed_id)
                history.append((seconds / 3600.0, "odblokowana %s" % breed_id))
        for breed_id in sorted(unlocked, key=lambda b: -BREEDS[b]["price"]):
            if hens.get(breed_id, 0) > 0 or money < BREEDS[breed_id]["price"] * 2:
                continue
            if total_birds + 2 > capacity:
                continue
            money -= BREEDS[breed_id]["price"]
            hens[breed_id] = hens.get(breed_id, 0) + 1
            # Bez koguta tej rasy kury nie zniosa nic, wiec gracz kupuje go
            # razem z pierwsza kura. To podwaja koszt wejscia w rase.
            if roosters.get(breed_id, 0) == 0 and money >= BREEDS[breed_id]["price"]:
                money -= BREEDS[breed_id]["price"]
                roosters[breed_id] = 1
            if breed_id not in owned_ever:
                owned_ever.add(breed_id)
                history.append((seconds / 3600.0,
                                "kupiona pierwsza %s za %d zl" % (breed_id, BREEDS[breed_id]["price"])))

        # --- warunki wygranej -------------------------------------------
        extra = {"fox_visits": fox_visits, "vaccine_spent": vaccine_spent, "starved": starved}
        if money >= goal:
            return dict(hours=seconds / 3600.0, history=history, hens=dict(hens),
                        money=money, won=True, by="milion zlotych", **extra)
        if BALANCE["win"].get("collection") and all(hens.get(b, 0) > 0 for b in BREEDS):
            return dict(hours=seconds / 3600.0, history=history, hens=dict(hens),
                        money=money, won=True, by="pelna kolekcja", **extra)

    return dict(hours=MAX_HOURS, history=history, hens=dict(hens), money=money,
                won=False, fox_visits=fox_visits, vaccine_spent=vaccine_spent, starved=starved)


if __name__ == "__main__":
    start_slots = BALANCE["incubator"]["slots"]
    max_slots = BALANCE["incubator"]["upgrades"][-1]["slots"]
    print("rasa            jajko    cena  sprzedaz   zwrot z jaj    hodowla/h (%d slotow)" % max_slots)
    for breed_id, breed in BREEDS.items():
        payback = payback_minutes(breed_id)
        payback_text = "%6.0f min" % payback if payback != float("inf") else "    nigdy"
        print("%-12s %6.2f %7d %9d %13s %14.0f" % (
            breed_id, breed["egg_value"], breed["price"], breed["sell_price"],
            payback_text, breeding_profit_per_hour(breed_id, max_slots)))

    print("\nsymulacja rozsadnego gracza (start: %d slotow):" % start_slots)
    result = simulate()
    for hours, what in result["history"]:
        print("  %6.1f h  %s" % (hours, what))
    if result["won"]:
        print("  WYGRANA po %.1f h gry (%s), konto %.0f zl" % (
            result["hours"], result["by"], result["money"]))
    else:
        print("  BRAK WYGRANEJ w %d h, konto %.0f zl — ekonomia za wolna" % (
            MAX_HOURS, result["money"]))
    print("  lis przyszedl %d razy, szczepienia kosztowaly %.0f zl"
          % (result["fox_visits"], result["vaccine_spent"]))
    print("  stado na koncu: %d kur" % sum(result["hens"].values()))
    if result["starved"]:
        print("  uwaga: %d sekund bez paszy" % result["starved"])
