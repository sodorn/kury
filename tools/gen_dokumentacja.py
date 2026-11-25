#!/usr/bin/env python3
"""Sklada DOKUMENTACJA_TECHNICZNA.txt - dokumentacje dla programisty.

Tekst opisowy siedzi tutaj. Wszystko, co sie zmienia - wartosci konfiguracji,
tabele ras i budynkow, lista sygnalow, wersja formatu zapisu, lista
workflowow - jest czytane z plikow projektu przy kazdym uruchomieniu.

    python3 -I tools/gen_dokumentacja.py           # przegeneruj plik
    python3 -I tools/gen_dokumentacja.py --check   # tylko sprawdz

Tryb --check konczy sie bledem, gdy:
  * w balance.json albo breeds.json jest klucz bez opisu w OPISY ponizej,
  * w OPISY jest opis klucza, ktorego juz nie ma (martwy opis),
  * DOKUMENTACJA_TECHNICZNA.txt nie zgadza sie z tym, co skrypt by wygenerowal.
Uzywa go GitHub Actions przed kazdym wdrozeniem.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "DOKUMENTACJA_TECHNICZNA.txt"
BAL = json.loads((ROOT / "data" / "balance.json").read_text(encoding="utf-8"))
BREEDS = json.loads((ROOT / "data" / "breeds.json").read_text(encoding="utf-8"))
BACKEND = json.loads((ROOT / "data" / "backend.json").read_text(encoding="utf-8"))
SCALE = float(BAL["offline"]["scale"])
W = 78

# ===========================================================================
# OPISY KLUCZY KONFIGURACJI
#   klucz: (jednostka, opis, gdzie uzywane)
# Jednostki czasu:
#   ZEGAR - czas rzeczywisty (to, co pokazuje zegarek)
#   GRA   - czas gry; plynie `offline.scale` razy szybciej... a konkretnie
#           1 s zegara = offline.scale s gry, wiec X s GRY = X / scale s zegara
# Klucze zaczynajace sie od "_" w plikach JSON to komentarze - gra je pomija.
# ===========================================================================
OPISY = {
    # ---------------------------------------------------------------- start
    "start.money": ("zl", "Pieniadze nowej fermy.", "Game.new_game"),
    "start.eggs": ("szt.", "Jaja w magazynie nowej fermy.", "Game.new_game"),
    "start.feed": ("kg", "Pasza w magazynie nowej fermy.", "Game.new_game"),
    "start.hens": ("lista id ras", "Kury nowej fermy - po jednym wpisie na sztuke. Id z breeds.json.",
                   "Game.new_game"),
    "start.roosters": ("lista id ras", "Koguty nowej fermy. Bez koguta danej rasy jej kury nie znosza.",
                       "Game.new_game"),
    # -------------------------------------------------------------- economy
    "economy.feed_pack_size": ("kg", "Wielkosc worka paszy przy magazynie na poziomie 0. Wyzsze "
                               "poziomy maja wlasne worki (buildings.storage.upgrades[].pack_size). "
                               "Razem z feed_pack_price wyznacza CENE BAZOWA kilograma, od ktorej "
                               "liczy sie rabaty hurtowe.",
                               "FarmState.feed_pack(), panel sklepu"),
    "economy.feed_pack_price": ("zl", "Cena worka paszy przy magazynie na poziomie 0.",
                                "FarmState.feed_pack(), panel sklepu"),
    "economy.rooster_price_multiplier": ("mnoznik", "Cena koguta = cena kury tej samej rasy razy ta "
                                         "liczba. 2.5 oznacza 250%.", "FarmState.hen_buy_price"),
    "economy.feed_per_hen_minute": ("kg / min GRY", "Ile paszy zjada jeden dorosly ptak (kura albo "
                                    "kogut) na minute GRY. Na godzine zegara: wartosc * 60 * scale.",
                                    "FarmState.feed_per_minute, Simulation._step"),
    "economy.chick_feed_multiplier": ("mnoznik", "Pisklę zjada tyle razy wiecej niz dorosly ptak "
                                      "(0.5 = polowe).", "FarmState.feed_per_minute"),
    "economy.egg_sale_lot": ("szt.", "Ile jaj sprzedaje jedno dotkniecie przycisku w sklepie. "
                             "Najstarsze najpierw, bez wzgledu na rase. Mniej jaj niz partia = "
                             "sprzedaje resztke.", "Game.sell_eggs, Game.egg_sale_lot"),
    "economy.egg_spoil_hours": ("h ZEGARA", "Po tylu godzinach niesprzedane jajo w magazynie gnije "
                                "i znika. 0 wylacza gnicie. Wiek jaj trzyma FarmState.egg_ages.",
                                "Simulation._advance_egg_spoilage, FarmState.age_eggs"),
    "economy.feed_bulk_packs": ("szt.", "Ile workow kupuje przycisk hurtowy w sklepie (\"Kup 10 "
                                "workow\"). Kupuje wszystkie albo zaden.",
                                "Game.buy_feed, Game.feed_bulk_packs"),
    # ------------------------------------------------------------------ run
    "run.max_eggs_on_ground": ("szt.", "Ile jaj moze lezec naraz na trawie do zebrania palcem. "
                               "Nadmiar idzie prosto do magazynu (o ile jest miejsce).",
                               "Simulation._lay_eggs"),
    "run.max_visible_hens": ("szt.", "Ile kur najwyzej rysujemy na wybiegu. Stado moze byc wieksze - "
                             "reszta jest w kurniku. Chroni wydajnosc na telefonach.",
                             "scenes/farm/farm.gd"),
    "run.area.x": ("px", "Lewa krawedz wybiegu we wspolrzednych sceny 1080x1920.", "scenes/farm/*"),
    "run.area.y": ("px", "Gorna krawedz wybiegu.", "scenes/farm/*"),
    "run.area.w": ("px", "Szerokosc wybiegu.", "scenes/farm/*"),
    "run.area.h": ("px", "Wysokosc wybiegu.", "scenes/farm/*"),
    "run.pickup_radius": ("px", "Dotkniecie zbiera wszystkie jaja w tym promieniu, a nie tylko jedno.",
                          "scenes/farm/ground_egg.gd"),
    # -------------------------------------------------------------- offline
    "offline.max_hours": ("h ZEGARA", "Najdluzsza przerwa rozliczana po powrocie. Dluzsza nieobecnosc "
                          "liczy sie jak ta liczba godzin.", "Game._apply_elapsed"),
    "offline.scale": ("mnoznik", "TEMPO GRY. Sekunda zegara to tyle sekund gry. 1/3 = gra plynie trzy "
                      "razy wolniej od zegara. Zmiana przelicza WSZYSTKIE czasy oznaczone GRA - "
                      "zmieniaj ostroznie.", "GameData.time_scale, wszedzie"),
    # ------------------------------------------------------------------ day
    "day.seconds": ("s GRY", "Dlugosc doby gospodarstwa (licznik dni w interfejsie).",
                    "Simulation._advance_days"),
    # ------------------------------------------------------------ incubator
    "incubator.slots": ("szt.", "Miejsca w inkubatorze na poziomie 0. Jedno miejsce = jedna partia "
                        "(jedno pisklę) naraz.", "FarmState.incubator_slots"),
    "incubator.eggs_per_chick": ("szt.", "Ile jaj tej samej rasy idzie na jedno pisklę.",
                                 "Game.incubate"),
    "incubator.rooster_share": ("0..1", "Jaka czesc wyklutych piskląt to kogutki. 0.5 = jak w naturze, "
                                "pol na pol. Plec losowana przy wykluciu, zapisywana w pisklęciu "
                                "(\"rooster\" w zapisie).", "Chick.roll_rooster, Simulation._advance_incubator"),
    "incubator.upgrades[].name": ("klucz tekstu", "Nazwa poziomu z data/strings.csv.", "panel inkubatora"),
    "incubator.upgrades[].slots": ("szt.", "Miejsca w inkubatorze na tym poziomie.",
                                   "FarmState.incubator_slots"),
    "incubator.upgrades[].price": ("zl", "Cena przejscia NA ten poziom.", "Game.upgrade_incubator"),
    "incubator.name": ("klucz tekstu", "Nazwa poziomu startowego inkubatora (poziom 1 w panelu).",
                       "panel inkubatora"),
    "incubator.upgrades[].build_minutes": ("min ZEGARA", "Ile minut REALNYCH trwa budowa tego poziomu. Placi sie od razu, "
                 "nowy poziom wchodzi po skonczeniu; w trakcie budynek dziala na starym. "
                 "0 albo brak = od razu.", "Game.upgrade_building, Simulation._advance_construction"),
    # --------------------------------------------------------------- hunger
    "hunger.grace_minutes": ("min GRY", "Po skonczeniu paszy przez tyle minut nic sie nie dzieje. "
                             "Potem zaczynaja padac kury.", "Simulation._advance_hunger"),
    "hunger.death_interval_seconds": ("s GRY", "Odstep miedzy kolejnymi padnieciami z glodu przy stadzie "
                                      "o wielkosci reference_hens. Wieksze stado pada proporcjonalnie "
                                      "szybciej: odstep = ta liczba / max(1, stado / reference_hens).",
                                      "Simulation._advance_hunger"),
    "hunger.corpse_seconds": ("s GRY", "Jak dlugo zwloki (z glodu, choroby, lisa) leza na wybiegu.",
                              "core/model/corpse.gd"),
    "hunger.offline_max_share": ("0-1", "Przy nadrabianiu nieobecnosci stado moze stracic najwyzej taki "
                                 "ulamek (glod + choroba + lis RAZEM). Powrot do gry nie moze oznaczac "
                                 "pustego wybiegu.", "Simulation.advance (loss_budget)"),
    "hunger.reference_hens": ("szt.", "Wielkosc stada, dla ktorej obowiazuje goly death_interval_seconds.",
                              "Simulation._advance_hunger"),
    # -------------------------------------------------------------- disease
    "disease.death_minutes": ("min ZEGARA", "Chora kura pada po tylu minutach REALNYCH. Leku nie ma "
                              "(od 12.20).", "Simulation._advance_disease"),
    "disease.vaccine_price": ("zl", "Stala czesc ceny szczepienia calego stada (niezalezna od liczby "
                              "kur). Cena = ta liczba + vaccine_price_per_hen * zdrowe niezaszczepione.",
                              "Game.vaccine_price"),
    "disease.vaccine_price_per_hen": ("zl / szt.", "Zmienna czesc ceny szczepienia, za kazdego "
                                      "ZDROWEGO niezaszczepionego ptaka. Szczepionka nie leczy.",
                                      "Game.vaccine_price, Game.buy_vaccine"),
    "disease.grace_minutes": ("min ZEGARA", "Przez tyle minut od zalozenia fermy nikt nie choruje.",
                              "Simulation._advance_disease"),
    "disease.mcdonalds_price": ("zl", "Ile skup placi za chora kure (kazda rasa tyle samo). Jedyne "
                                "wyjscie z chora sztuka.", "Game.cull_hen, Game.mcdonalds_price"),
    "disease.roll_seconds": ("s ZEGARA", "Co tyle sekund leci kostka na wybuch choroby (gra aktywna "
                             "i w tle tak samo).", "Simulation._advance_disease"),
    "disease.rate_per_hour": ("lista [ptaki, szansa/h]", "Krzywa szansy na wybuch na GODZINE od "
                              "wielkosci stada (dorosle ptaki). Miedzy punktami liniowo, ponizej "
                              "pierwszego i powyzej ostatniego plasko. Szansa jednej kostki = "
                              "szansa/h * roll_seconds / 3600.",
                              "FarmState.disease_rate_per_hour"),
    "disease.spread_seconds": ("s ZEGARA", "W trakcie ogniska co tyle sekund zaraza przechodzi na "
                               "kolejna zdrowa, niezaszczepiona kure.", "Simulation._spread_outbreak"),
    "disease.kill_share_min": ("0-1", "Najmniejsza czesc stada, jaka zarazi jedno ognisko.",
                               "Simulation._start_outbreak"),
    "disease.kill_share_max": ("0-1", "Najwieksza czesc stada w jednym ognisku.",
                               "Simulation._start_outbreak"),
    "disease.kill_share_step": ("0-1", "Krok losowania udzialu (0.1 = 30%, 40% ... 100%). Liczba kur "
                                "zaokraglana w gore.", "Simulation._start_outbreak"),
    "disease.calm_hours_min": ("h ZEGARA", "Najkrotszy spokoj po wygasnieciu ogniska (kostka nie "
                               "rzuca).", "Simulation._end_outbreak"),
    "disease.calm_hours_max": ("h ZEGARA", "Najdluzszy spokoj po ognisku. Losowany z przedzialu "
                               "min..max.", "Simulation._end_outbreak"),
    # ------------------------------------------------------------------ fox
    "fox.grace_minutes": ("min ZEGARA", "Przez tyle minut od zalozenia fermy lis nie przychodzi.",
                          "Simulation._advance_fox"),
    "fox.min_hens": ("szt.", "Przy mniejszym stadzie lis nie przychodzi.", "Simulation._advance_fox"),
    "fox.active_roll_minutes": ("min ZEGARA", "W GRZE AKTYWNEJ co tyle minut leci kostka na przyjscie "
                                "lisa.", "Simulation._advance_fox"),
    "fox.active_chance": ("0-1", "Szansa, ze kostka w grze aktywnej przyprowadzi lisa.",
                          "Simulation._advance_fox"),
    "fox.offline_roll_hours": ("h ZEGARA", "Przy grze w tle kostka co tyle godzin.",
                               "Simulation._advance_fox"),
    "fox.offline_chance": ("0-1", "Szansa kostki przy grze w tle.", "Simulation._advance_fox"),
    "fox.scare_taps": ("szt.", "Ile dotkniec trzeba, zeby przegonic lisa palcem.",
                       "Game.poke_fox, scenes/farm/fox.gd (licznik)"),
    "fox.hand_return_factor": ("mnoznik 0.01-1", "Lis przegoniony PALCEM wraca tyle razy szybciej "
                               "(odstep kostki mnozony przez te liczbe). Nie dziala, gdy ferma ma psa "
                               "albo plot.", "Simulation._advance_fox"),
    "fox.carcass_share": ("0-1", "Szansa, ze zabita przez lisa kura zostanie na wybiegu jako zwloki. "
                          "Reszte lis wynosi.", "Simulation._fox_grabs_one"),
    "fox.kill_interval_min": ("s ZEGARA", "Najkrotszy odstep miedzy kolejnymi zabitymi kurami. Kazdy "
                              "odstep losowany od nowa z przedzialu min..max.", "Simulation._advance_fox"),
    "fox.kill_interval_max": ("s ZEGARA", "Najdluzszy taki odstep.", "Simulation._advance_fox"),
    "fox.kills_min": ("szt.", "Najmniejszy lup lisa. Lup losowany przy wejsciu z przedzialu min..max; "
                      "po jego zebraniu lis odchodzi.", "Simulation._fox_arrives"),
    "fox.kills_max": ("szt.", "Najwiekszy lup lisa.", "Simulation._fox_arrives"),
    "fox.visit_max_minutes": ("min ZEGARA", "Bezpiecznik: lis nie zostaje dluzej, nawet gdy nie zebral "
                              "lupu (np. przez limit strat przy nadrabianiu).",
                              "FarmState.fox_visit_seconds"),
    "fox.lurk_min_seconds": ("s ZEGARA", "Najkrocej, ile lis czai sie w krzakach (gra AKTYWNA), zanim "
                             "ruszy pod plot. Przy grze w tle faza jest pomijana.",
                             "FarmState.fox_lurk_seconds, FarmFox.lurk"),
    "fox.lurk_max_seconds": ("s ZEGARA", "Najdluzej, ile lis czai sie w krzakach. Czas losowany "
                             "z przedzialu min..max.", "FarmState.fox_lurk_seconds"),
    "fox.approach_seconds": ("s ZEGARA", "Ile trwa droga lisa z krzaka pod plot. Dopiero gdy dojdzie, "
                             "plot losuje (block_chance), czy go zawroci. Wszystkie trzy na 0 "
                             "wylaczaja faze - lis wchodzi od razu.", "Simulation._fox_at_fence"),
    "fox.killed_return_multiplier": ("mnoznik", "Po ZAGRYZIENIU lisa przez psa odstep do nastepnej "
                                     "kostki jest tyle razy dluzszy.", "Simulation._advance_fox"),
    "fox.massacre_chance": ("0-1", "Szansa, ze lis, ktory wszedl na wybieg fermy BEZ psa, wybije cale "
                            "stado (rzez). Z psem nigdy.", "Simulation._fox_arrives"),
    "fox.massacre_pace_factor": ("mnoznik 0.05-1", "W rzezi odstep miedzy ofiarami jest mnozony przez "
                                 "te liczbe (lis zabija szybciej).", "Simulation._fox_kill_gap"),
    # ------------------------------------------------------------------ win
    "win.money": ("zl", "Wygrana po uzbieraniu tylu pieniedzy.", "Simulation.check_win"),
    "win.collection": ("tak/nie", "true = wygrana takze za zebranie wszystkich ras.",
                       "Simulation.check_win"),
    # -------------------------------------------------------------- buildings
    "buildings.coop.capacity": ("szt.", "Miejsca w kurniku na poziomie 0 (dorosle ptaki, z kogutami).",
                                "FarmState.coop_capacity"),
    "buildings.coop.upgrades[].name": ("klucz tekstu", "Nazwa poziomu kurnika.", "panel kurnika"),
    "buildings.coop.upgrades[].capacity": ("szt.", "Miejsca w kurniku na tym poziomie.",
                                           "FarmState.coop_capacity"),
    "buildings.coop.upgrades[].price": ("zl", "Cena przejscia NA ten poziom.", "Game.upgrade_building"),
    "buildings.coop.name": ("klucz tekstu", "Nazwa poziomu startowego kurnika.", "panel kurnika"),
    "buildings.coop.upgrades[].build_minutes": ("min ZEGARA", "Ile minut REALNYCH trwa budowa tego poziomu. Placi sie od razu, "
                 "nowy poziom wchodzi po skonczeniu; w trakcie budynek dziala na starym. "
                 "0 albo brak = od razu.", "Game.upgrade_building, Simulation._advance_construction"),
    "buildings.storage.egg_capacity": ("szt.", "Limit jaj w magazynie na poziomie 0.",
                                       "FarmState.egg_capacity"),
    "buildings.storage.upgrades[].name": ("klucz tekstu", "Nazwa poziomu magazynu.", "panel magazynu"),
    "buildings.storage.upgrades[].pack_size": ("kg", "Worek paszy na tym poziomie.", "FarmState.feed_pack"),
    "buildings.storage.upgrades[].pack_discount": ("0-1", "Rabat hurtowy na pasze na tym poziomie "
                                                   "(0.10 = 10%). Cena worka = pack_size * cena bazowa "
                                                   "za kg (economy.feed_pack_price / feed_pack_size) * "
                                                   "(1 - rabat), do pelnych groszy. Musi rosnac z "
                                                   "poziomem (test).", "FarmState.feed_pack"),
    "buildings.storage.upgrades[].price": ("zl", "Cena przejscia NA ten poziom.", "Game.upgrade_building"),
    "buildings.storage.name": ("klucz tekstu", "Nazwa poziomu startowego magazynu.", "panel magazynu"),
    "buildings.storage.upgrades[].build_minutes": ("min ZEGARA", "Ile minut REALNYCH trwa budowa tego poziomu. Placi sie od razu, "
                 "nowy poziom wchodzi po skonczeniu; w trakcie budynek dziala na starym. "
                 "0 albo brak = od razu.", "Game.upgrade_building, Simulation._advance_construction"),
    "buildings.storage.upgrades[].egg_capacity": ("szt.", "Limit jaj na tym poziomie.",
                                                  "FarmState.egg_capacity"),
    "buildings.guard.upgrades[].block_chance": ("0-1", "Szansa, ze lis po udanej kostce ZAWROCI przy "
                                                "plocie i w ogole nie wejdzie.",
                                                "FarmState.fox_block_chance"),
    "buildings.guard.upgrades[].price": ("zl", "Cena tego poziomu plotu. Poziomow musi byc 4 - tyle "
                                         "jest grafik (tools/gen_fence.py).", "Game.upgrade_building"),
    "buildings.dog.upgrades[].name": ("tekst", "Nazwa psa w panelu. Indeks 0 = kundel, 1 = owczarek "
                                      "(od indeksu zalezy grafika).", "panel kurnika, scenes/farm/dog.gd"),
    "buildings.dog.upgrades[].interval": ("s ZEGARA", "Co tyle sekund wizyty lisa pies rzuca kostka.",
                                          "FarmState.dog_interval"),
    "buildings.dog.upgrades[].chance": ("0-1", "Szansa, ze rzut sie uda i lis wyleci z wybiegu.",
                                        "FarmState.dog_chance"),
    "buildings.dog.upgrades[].kill_chance": ("0-1", "Przy udanym rzucie: szansa, ze pies lisa ZAGRYZIE "
                                             "(zamiast tylko przegonic).", "FarmState.dog_kill_chance"),
    "buildings.dog.upgrades[].price": ("zl", "Cena psa.", "Game.upgrade_building"),
    # --------------------------------------------------------------- session
    "session.require_code": ("tak/nie", "true = przy wejsciu do gry trzeba wpisac kod fermy, a stan "
                             "przychodzi z serwera. Dziala tylko przy wlaczonym backendzie.",
                             "Game.must_enter_code"),
    "session.require_code_after_minutes": ("min ZEGARA", "0 = kod przy KAZDYM wejsciu. Liczba > 0 = "
                                           "dopiero po takiej przerwie.", "Game.must_enter_code"),
}

OPISY_RAS = {
    "id": ("tekst", "Identyfikator rasy. Uzywany w zapisach graczy - NIE ZMIENIAC istniejacych."),
    "name": ("klucz tekstu", "Nazwa rasy (data/strings.csv)."),
    "desc": ("klucz tekstu", "Krotki opis w sklepie."),
    "lore": ("klucz tekstu", "Dluzszy opis w oknie nowej rasy."),
    "rarity": ("klucz tekstu", "Rzadkosc (RARITY_COMMON itp.) - tylko napis."),
    "sprite": ("sciezka res://", "Grafika kury na wybiegu."),
    "rooster_sprite": ("sciezka res://", "Grafika koguta."),
    "photo": ("sciezka res://", "Zdjecie rasy (zapasowe - plikow na razie nie ma)."),
    "portrait": ("sciezka res://", "Malowany portret rasy (tools/gen_portraits.py) w sklepie i w oknie "
                 "nowej rasy. Pierwszy wybor przed zdjeciem i rysunkiem z wybiegu."),
    "facts": ("lista kluczy tekstu", "Trzy ciekawostki o rasie w oknie nowej rasy (sprawdzone "
              "w zrodlach)."),
    "egg_seconds": ("s GRY", "Co tyle sekund gry kura znosi jajo."),
    "egg_value": ("zl", "Cena sprzedazy jednego jaja."),
    "price": ("zl", "Cena kupna kury. Kogut = price * economy.rooster_price_multiplier."),
    "sell_price": ("zl", "Cena sprzedazy zdrowej doroslej sztuki. Zwyczajowo 70% price."),
    "incubate_seconds": ("s GRY", "Czas w inkubatorze do wyklucia."),
    "grow_seconds": ("s GRY", "Czas odchowu pisklecia do doroslej sztuki."),
    "coop_level": ("poziom", "Od tego poziomu kurnika rasa jest w sklepie."),
    "egg_tint": ("kolor #RRGGBB, opcjonalne", "Kolor skorupki jaja tej rasy na wybiegu. Brak pola = "
                 "jajo biale."),
    "feather_colors": ("lista kolorow #RRGGBB", "Kolory piór, ktore sypia sie fontanna, gdy lis "
                       "dopadnie kure tej rasy. Brak pola = biale."),
    "incubation_bonus": ("liczba, opcjonalne", "Kazda DOROSLA kura tej rasy na fermie przyspiesza "
                         "inkubator: predkosc = 1 + suma bonusow, najwyzej 2,5 raza "
                         "(FarmState.incubation_speed). Ma je jedwabista - kwoka."),
}

# ===========================================================================
L = []


def raw(text=""):
    L.append(text)


def rule(ch="="):
    L.append(ch * W)


def title(text):
    if L and L[-1].strip():
        L.append("")
    rule("=")
    L.append(" " + text.upper())
    rule("=")


def head(text):
    if L and L[-1].strip():
        L.append("")
    L.append("  " + text)
    L.append("  " + "-" * len(text))


def para(text, indent="  "):
    for block in text.strip("\n").split("\n\n"):
        block = " ".join(block.split())
        if not block:
            continue
        if L and L[-1].strip():
            L.append("")
        line = indent
        for word in block.split():
            if len(line) + len(word) > W and line.strip():
                L.append(line.rstrip())
                line = indent
            line += word + " "
        L.append(line.rstrip())


def block(text):
    """Tekst wstawiany znak w znak (schematy, kod, tabele)."""
    if L and L[-1].strip():
        L.append("")
    for line in text.strip("\n").split("\n"):
        L.append(line.rstrip())


def table(headers, rows, align=""):
    cols = len(headers)
    align = (align + "l" * cols)[:cols]
    widths = [len(str(h)) for h in headers]
    for r in rows:
        for i, c in enumerate(r):
            widths[i] = max(widths[i], len(str(c)))

    def line(ch):
        return "  +" + "+".join(ch * (w + 2) for w in widths) + "+"

    def row(cells):
        out = []
        for i, c in enumerate(cells):
            t = str(c)
            out.append(" " + (t.rjust(widths[i]) if align[i] == "r" else t.ljust(widths[i])) + " ")
        return "  |" + "|".join(out) + "|"

    if L and L[-1].strip():
        L.append("")
    L.append(line("="))
    L.append(row(headers))
    L.append(line("="))
    for r in rows:
        L.append(row(r))
    L.append(line("-"))


def wrap_into(text, indent):
    out, line = [], indent
    for word in text.split():
        if len(line) + len(word) > W and line.strip():
            out.append(line.rstrip())
            line = indent
        line += word + " "
    out.append(line.rstrip())
    return out


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        if abs(v - round(v)) < 1e-9:
            return "%.1f" % v
        return ("%.4f" % v).rstrip("0")
    if isinstance(v, list):
        return json.dumps(v, ensure_ascii=False)
    return str(v)


# --------------------------------------------------------------------------
def leaves(node, prefix=""):
    """Wszystkie klucze konfiguracji. Listy slownikow -> klucz[]."""
    out = []
    if isinstance(node, dict):
        for k, v in node.items():
            if k.startswith("_"):
                continue
            path = prefix + "." + k if prefix else k
            if isinstance(v, list) and v and isinstance(v[0], dict):
                fields = []
                for entry in v:
                    for f in entry:
                        if not f.startswith("_") and f not in fields:
                            fields.append(f)
                for f in fields:
                    out.append((path + "[]." + f, [e.get(f) for e in v]))
            elif isinstance(v, dict):
                out.extend(leaves(v, path))
            else:
                out.append((path, v))
    return out


def project_version():
    m = re.search(r'config/version="([^"]+)"', (ROOT / "project.godot").read_text(encoding="utf-8"))
    return m.group(1) if m else "?"


def save_version():
    m = re.search(r"^const VERSION := (\d+)", (ROOT / "core" / "save_game.gd").read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else "?"


def signals():
    out = []
    for line in (ROOT / "services" / "events.gd").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^signal\s+(.+)$", line.strip())
        if m:
            out.append(m.group(1))
    return out


def autoloads():
    text = (ROOT / "project.godot").read_text(encoding="utf-8")
    sec = text.split("[autoload]", 1)[1].split("\n[", 1)[0]
    return re.findall(r'^(\w+)="\*?(res://[^"]+)"', sec, re.M)


def workflows():
    out = []
    for f in sorted((ROOT / ".github" / "workflows").glob("*.yml")):
        text = f.read_text(encoding="utf-8")
        name = re.search(r"^name:\s*(.+)$", text, re.M)
        cron = re.search(r'cron:\s*"([^"]+)"', text)
        trig = []
        if cron:
            trig.append("cron " + cron.group(1) + " (UTC)")
        if re.search(r"^\s*push:", text, re.M):
            trig.append("push na main")
        if "workflow_dispatch" in text:
            trig.append("recznie")
        out.append((f.name, name.group(1).strip() if name else "?", ", ".join(trig)))
    return out


def check_keys():
    """Zwraca (brakujace opisy, martwe opisy)."""
    have = {k for k, _ in leaves(BAL)}
    missing = sorted(have - set(OPISY))
    dead = sorted(set(OPISY) - have)
    breed_fields = set()
    for b in BREEDS:
        breed_fields |= {k for k in b if not k.startswith("_")}
    missing += sorted("breeds.json:" + f for f in breed_fields - set(OPISY_RAS))
    dead += sorted("breeds.json:" + f for f in set(OPISY_RAS) - breed_fields)
    return missing, dead


# ===========================================================================
def build():
    L.clear()
    v = project_version()
    rule("=")
    raw("  SYMULATOR HODOWLI KURCZAKOW - DOKUMENTACJA TECHNICZNA")
    raw("  gra w wersji %s   *   format zapisu w wersji %s   *   Godot 4.7.2" % (v, save_version()))
    rule("=")
    para("Dokument dla programisty: jak gra jest zbudowana, jak dzialaja mechaniki, co oznacza kazda "
         "liczba w konfiguracji, jak dziala serwer i jak gra trafia do graczy. Plik generuje "
         "tools/gen_dokumentacja.py - nie poprawiaj go recznie. Wszystkie wartosci w tabelach sa "
         "wziete z plikow gry w chwili generowania.")
    block("""
  SPIS TRESCI
     1. Z czego sklada sie gra
     2. Katalogi i pliki
     3. Start gry krok po kroku
     4. Czas: zegar, czas gry, nieobecnosc
     5. Petla symulacji
     6. Mechaniki zdarzen - szczegolowo
     7. KONFIGURACJA - wszystkie zmienne
     8. Model danych
     9. Zapis gry - format i migracje
    10. Serwer: Supabase od podstaw
    11. Synchronizacja z serwerem
    12. Budowanie, wdrazanie, aktualizacje w otwartych kartach
    13. GitHub Actions
    14. Testy i reguly pilnowane w konfiguracji
    15. Narzedzia w tools/
    16. Przepisy: typowe zmiany krok po kroku
    17. Znane ryzyka i ograniczenia""")

    # ------------------------------------------------------------------ 1
    title("1. Z czego sklada sie gra")
    block("""
   +------------------+   pobiera gre    +--------------------------------+
   |  PRZEGLADARKA    | <--------------- |  GitHub Pages                  |
   |  gracza          |   (HTTPS)        |  galaz gh-pages repo sodorn/   |
   |                  |                  |  kury: index.html, pack-*.txt, |
   |  Godot 4.7.2     |                  |  engine-*.txt, version.json    |
   |  jako WebAssembly|                  +--------------------------------+
   |                  |                                ^
   |  zapis lokalny:  |                                | wdraza
   |  user:// =       |                  +--------------------------------+
   |  IndexedDB       |                  |  GitHub Actions                |
   +------------------+                  |  test -> build -> wdrozenie    |
            |  ^                         |  po kazdym pushu na main       |
   zapis    |  | odczyt                  +--------------------------------+
   (POST)   v  | (GET)                                 ^
   +------------------+                                | git push
   |  Supabase        |                  +--------------------------------+
   |  PostgreSQL +    |                  |  repo sodorn/kury, galaz main  |
   |  REST (PostgREST)|                  |  zrodla gry + data/*.json      |
   |  tabela "saves"  |                  +--------------------------------+
   +------------------+""")
    para("Gra to projekt Godot 4.7.2 w GDScript, eksportowany do przegladarki (WebAssembly, bez "
         "watkow, bez rozszerzen GDExtension). Uklad pionowy 1080x1920, renderer GL Compatibility. "
         "Nie ma wlasnego serwera aplikacji: gra jest zestawem plikow statycznych na GitHub Pages, "
         "a stan farm lezy w bazie PostgreSQL w Supabase, do ktorej przegladarka gada bezposrednio "
         "przez REST.")
    para("Cala logika gry dziala w przegladarce gracza. Serwer tylko przechowuje zapisy - niczego "
         "nie liczy i niczego nie sprawdza.")

    # ------------------------------------------------------------------ 2
    title("2. Katalogi i pliki")
    block("""
  project.godot          ustawienia projektu, WERSJA GRY (config/version),
                         lista autoloadow
  export_presets.cfg     ustawienia eksportu (Web, Android)
  data/
    balance.json         CALA liczbowa konfiguracja mechanik (rozdzial 7)
    breeds.json          17 ras: ceny, czasy, grafiki
    buildings.json       budynki na fermie: id + klucze tekstow
    backend.json         adres i klucz Supabase, wlacznik backendu
    strings.csv          wszystkie teksty (klucz -> tekst po polsku)
  core/                  LOGIKA BEZ GRAFIKI - da sie testowac bez okna
    simulation.gd        Simulation.advance(): jeden krok swiata gry
    save_game.gd         zapis/odczyt JSON, migracje starych zapisow
    model/farm_state.gd  caly stan fermy (pieniadze, stado, poziomy...)
    model/chicken.gd     jeden ptak
    model/corpse.gd      zwloki na wybiegu
    util/game_data.gd    wczytuje data/*.json, GameData.VERSION
  services/              AUTOLOADY - zyja przez cala gre
    events.gd            szyna sygnalow miedzy logika a scenami
    game.gd              "mozg": czas, zakupy, zapis, synchronizacja
    cloud.gd             rozmowa z Supabase (HTTP)
    updater.gd           dowozenie nowej wersji do otwartych kart
  scenes/
    main/                scena glowna
    farm/                ferma: kury, lis, pies, budynki, jaja, zwloki
    ui/hud/              pasek zasobow na gorze
    ui/panels/           panele: budynki, sklep, start, nowa rasa, wygrana
  assets/                grafiki SVG, zdjecia ras, czcionki, motyw
  tests/
    run_tests.gd         testy logiki (bez okna), tests.tscn
    smoke_ui.gd          test dymny: prawdziwa gra z grafika, smoke_ui.tscn
    fox_lab.gd           laboratorium lisa (tylko pomiar, poza CI):
                         godot --headless --path . tests/fox_lab.tscn
    bot_24h.gd           bot gra pierwsza dobe trzema stylami (pomiar balansu,
                         poza CI): ... --path . tests/bot_24h.tscn
                         wyniki 12.18: docs/BOT_24H_12.18.txt
  tools/                 skrypty pomocnicze (rozdzial 15)
  docs/supabase.sql      definicja tabeli i polityk w bazie
  kopie/                 codzienne kopie wszystkich farm z serwera (JSON)
  .github/workflows/     automaty GitHub Actions (rozdzial 13)
  INSTRUKCJA.txt         instrukcja dla gracza (generowana)
  DOKUMENTACJA_TECHNICZNA.txt  ten plik (generowany)""")

    # ------------------------------------------------------------------ 3
    title("3. Start gry krok po kroku")
    head("Autoloady (w tej kolejnosci tworzy je Godot)")
    table(["nazwa", "plik"], autoloads())
    para("Autoload to wezel tworzony przez silnik przed scena glowna i dostepny z kazdego skryptu po "
         "nazwie (Game.state, Cloud.push(...)). Kolejnosc ma znaczenie: Game korzysta z Cloud "
         "i Events w swoim _ready, wiec musza istniec wczesniej.")
    head("Sekwencja")
    block("""
  1. Cloud._ready      czyta data/backend.json i kod fermy
                      z user://player_id.txt
  2. Game._ready      Game.load_or_start():
                        - jest lokalny zapis -> wczytaj, rozlicz czas od
                          zapisu (rozdzial 4), potem Cloud.pull() w tle
                        - brak zapisu -> nowa ferma w pamieci,
                          is_new_player = true (NIE pobiera z serwera,
                          bo nie wie, o jaki kod chodzi)
  3. Updater._ready   sprawdza znacznik "to bylo przeladowanie po
                      aktualizacji" (localStorage "kury_update")
  4. scena glowna     panel startowy pyta Game.should_show_intro() -
                      po aktualizacji NIE pokazuje sie wcale
  5. panel startowy   "Nowa ferma" -> Game.start_new_farm()
                      wpisany kod  -> Game.restore_from_code(kod)
                      Gdy session.require_code = true, przy kazdym
                      wejsciu trzeba wpisac kod (Game.must_enter_code)
  6. Cloud.pulled     odpowiedz serwera -> Game._on_cloud_pulled()
                      (zasady scalania w rozdziale 11)""")
    para("Dopoki panel startowy jest otwarty, symulacja stoi (Game.pause_simulation). Czas, ktory "
         "minal, nie przepada - zostaje rozliczony po zamknieciu panelu.")

    # ------------------------------------------------------------------ 4
    title("4. Czas: zegar, czas gry, nieobecnosc")
    para("W grze sa DWA zegary i trzeba je rozrozniac przy kazdej liczbie w konfiguracji:")
    block("""
  ZEGAR   czas rzeczywisty, ten ze zegarka.
  GRA     czas swiata gry. Plynie wolniej:  1 s zegara = %s s gry
          czyli:   X s GRY  =  X / %s s ZEGARA  =  X * %g s ZEGARA""" % (fmt(SCALE), fmt(SCALE), round(1 / SCALE, 4)))
    para("Funkcja Simulation.advance(state, delta) przyjmuje sekundy GRY. Mechaniki, ktore wlasciciel "
         "opisal w czasie rzeczywistym (lis, psy, choroba, gnicie jaj, karencje), same przeliczaja "
         "krok na zegar: real = step / GameData.time_scale(). Dlatego w rozdziale 7 przy kazdej "
         "zmiennej jest napisane, w ktorym zegarze sie liczy.")
    head("Petla czasu w Game._process")
    block("""
  co klatke:  elapsed = teraz - _last_tick         (ZEGAR, Time.get_unix_time)
              Game.apply_gap(elapsed, okno_aktywne)
                okno aktywne    -> rozlicz _away_seconds + elapsed:
                                   do %s s jako gra aktywna (advance),
                                   wiecej jako nieobecnosc (_apply_elapsed)
                okno nieaktywne -> NIE liczy, tylko dopisuje do
                                   _away_seconds (dlug czasu)
              autozapis co %s s ZEGARA (Game.AUTOSAVE_SECONDS)""" % (
        _const("MAX_LIVE_STEP"), _autosave()))
    para("Dlug czasu (_away_seconds) jedzie razem z zapisem: SaveGame.to_dict(state, unpaid_seconds) "
         "zapisuje saved_at = teraz - dlug. Pole saved_at oznacza wiec OSTATNIA POLICZONA chwile "
         "gospodarstwa, a nie moment zapisu pliku. Do wersji 12.11 kazdy autozapis wbijal swiezy "
         "stempel i noc spedzona z karta w tle przepadala.")
    head("Nieobecnosc (gra w tle, zamknieta karta)")
    block("""
  przy wczytaniu zapisu:   elapsed = teraz - saved_at        (ZEGAR)
  Game._apply_elapsed:     ogranicz do offline.max_hours = %s h
                           Simulation.advance(state, elapsed * scale,
                                              offline = true)""" % fmt(BAL["offline"]["max_hours"]))
    para("Tryb offline zmienia trzy rzeczy: (1) kostka lisa losuje z offline_roll_hours "
         "i offline_chance zamiast active_* (choroba ma jedna kostke na oba tryby), (2) jaja ida "
         "prosto do magazynu, nie na trawe, "
         "(3) straty z glodu, choroby i lisa RAZEM sa ograniczone do hunger.offline_max_share stada "
         "(loss_budget). Lis przy grze w tle rozgrywa cala wizyte od razu - z psem, ale bez "
         "klikania (Simulation._fox_visit_offline).")
    para("Dlugi krok jest dzielony na kawalki: Simulation.STEP = 1 s gry, przy przerwie dluzszej "
         "niz 600 s gry krok rosnie do najwyzej MAX_STEP = 10 s gry (zeby doba nieobecnosci "
         "liczyla sie ulamek sekundy, a nie minute).")

    # ------------------------------------------------------------------ 5
    title("5. Petla symulacji")
    para("Simulation._step(state, krok) - kolejnosc ma znaczenie i jest celowa:")
    block("""
   1. _advance_days          licznik dni (day.seconds)
   2. JESLI JEST PASZA:
        _advance_incubator   partie w inkubatorze -> piskleta
        _advance_chicks      piskleta rosna -> dorosle ptaki
   3. _advance_corpses       zwloki znikaja po hunger.corpse_seconds
      _advance_construction  budowy (czas ZEGARA) - koniec = poziom+1,
                             id do wyniku "built" (od 12.19)
   4. _advance_egg_spoilage  jaja starsze niz egg_spoil_hours gnija
                             (PRZED wyjsciem dla pustej fermy - jaja
                             gnija takze bez stada)
   5. _advance_fox           wizyta w toku / kostka na nowego lisa
   6. pasza                  jest -> zjedz feed_per_minute * krok,
                                     wyzeruj licznik glodu
                             brak -> _advance_hunger (glod zabija)
   7. pusta ferma?           koniec kroku
   8. _advance_disease       choroba: przebieg u chorych + kostka
   9. brak paszy?            koniec kroku (glodne kury nie znosza)
  10. _lay_eggs              znoszenie jaj""")
    para("Rozbudowa kurnika, magazynu i inkubatora trwa build_minutes minut zegara (5-60). "
         "Game.upgrade_building placi od razu i wpisuje FarmState.construction[id] = [zostalo, "
         "calosc]; budynek dziala na starym poziomie. Budowa idzie takze w tle i przezywa zapis "
         "(klucz \"construction\"). Plot i pies nie maja build_minutes - sa od razu. Na fermie nad "
         "budynkiem wisi tabliczka z zegarem (farm.gd _sync_construction).")
    para("Transakcje, ktore kiedys pytaly \"na pewno?\", i cala rozbudowa to SUWAK "
         "(scenes/ui/panels/slide_button.gd, klasa SlideButton dziedziczy po Button). Zwykle "
         "dotkniecie jest polykane w _gui_input, a sygnal pressed leci dopiero po przeciagnieciu "
         "do konca - kod podlaczony do pressed nic nie wie o suwaku. Zwykle przyciski zostaly "
         "przy sprzedazy jaj, paszy i wkladaniu jaj do inkubatora (klika sie je co chwile).")
    para("Wynik Simulation.advance to slownik licznikow (eggs_laid, hatched, grown_up, died_hunger, "
         "died_disease, got_sick, fox_took, fox_arrived, fox_blocked, fox_chased, fox_killed, "
         "rotted, eggs_spoiled ...). Game zamienia go na komunikaty i sygnaly (Game._report).")

    # ------------------------------------------------------------------ 6
    title("6. Mechaniki zdarzen - szczegolowo")
    fox, dis, hun = BAL["fox"], BAL["disease"], BAL["hunger"]

    head("6.1 Znoszenie jaj")
    para("Kazda kura ma licznik since_last_egg (s GRY). Po przekroczeniu egg_seconds swojej rasy "
         "znosi jajo. NIE znosza: koguty, chore kury, kury rasy bez koguta na fermie, cale stado "
         "przy braku paszy. Jajo w grze aktywnej laduje na trawie (do run.max_eggs_on_ground), "
         "reszta i wszystko przy grze w tle - w magazynie. Magazyn ma limit "
         "(FarmState.egg_capacity): jajo, ktore sie nie miesci, przepada. FarmState.add_egg zwraca, "
         "ile faktycznie weszlo.")
    para("Gnicie: FarmState.egg_ages trzyma wiek jaj kazdej rasy (ZEGAR). Jajo starsze niz "
         "economy.egg_spoil_hours (%s h) znika. Sklep sprzedaje partiami po economy.egg_sale_lot "
         "(%s) - FarmState.oldest_eggs wybiera NAJSTARSZE jaja ze wszystkich ras, bo te zgnija "
         "najpierw." % (fmt(BAL["economy"]["egg_spoil_hours"]), BAL["economy"]["egg_sale_lot"]))
    head("6.1a Pasza w hurcie")
    eco = BAL["economy"]
    per_kg = eco["feed_pack_price"] / eco["feed_pack_size"]
    rows = [["0", eco["feed_pack_size"], "0%", "%.2f" % (eco["feed_pack_size"] * per_kg), "%.2f" % per_kg]]
    for i, u in enumerate(BAL["buildings"]["storage"]["upgrades"], start=1):
        kg = per_kg * (1 - u["pack_discount"])
        rows.append([str(i), u["pack_size"], "%.0f%%" % (u["pack_discount"] * 100),
                     "%.2f" % round(u["pack_size"] * kg, 2), "%.2f" % kg])
    table(["magazyn", "worek kg", "rabat", "cena zl", "zl/kg"], rows, "rrrrr")

    head("6.2 Pasza i glod")
    block("""
  zuzycie na sekunde GRY = (dorosle + pisklęta * chick_feed_multiplier)
                           * feed_per_hen_minute / 60
  brak paszy:
    przez grace_minutes (%s min GRY = %s min zegara) nic sie nie dzieje
    potem co  death_interval_seconds / max(1, stado / reference_hens)
             = %s s GRY / max(1, stado / %s)   pada jedna losowa kura""" % (
        fmt(hun["grace_minutes"]), fmt(round(hun["grace_minutes"] / SCALE, 2)),
        fmt(hun["death_interval_seconds"]), fmt(hun["reference_hens"])))
    para("Bez paszy stoi tez inkubator i odchow - inaczej stado odnawialoby sie szybciej, niz "
         "gloduje.")

    head("6.3 Choroba (od 12.20: ogniska)")
    pts = ", ".join("%s->%s/h" % (p[0], fmt(p[1])) for p in dis["rate_per_hour"])
    block("""
  karencja:   pierwsze %s min ZEGARA fermy - nic
  kostka:     co %s s ZEGARA (gra aktywna i w tle tak samo)
              szansa = rate_per_hour(stado) * %s / 3600
              rate_per_hour: %s
              (miedzy punktami liniowo, poza nimi plasko)
  wybuch:     udzial = %s..%s co %s, liczba = ceil(stado * udzial)
              pierwsza kura od razu, kolejne co %s s ZEGARA
  kto:        tylko zdrowe i niezaszczepione; waga = sqrt(cena rasy)
  przebieg:   chora nie znosi; po %s min ZEGARA pada
  leczenie:   BRAK. Chora mozna tylko sprzedac do McDonalda za %s zl
  koniec:     nikt nie choruje i nie ma kogo zarazic -> spokoj
              %s..%s h ZEGARA (kostka nie rzuca)
  szczepienie: vaccine_price + vaccine_price_per_hen * zdrowe bez
              szczepienia = %s + %s * n zl; chroni zdrowe do konca
              zycia, chorych NIE leczy""" % (
        fmt(dis["grace_minutes"]), fmt(dis["roll_seconds"]), fmt(dis["roll_seconds"]), pts,
        fmt(dis["kill_share_min"]), fmt(dis["kill_share_max"]), fmt(dis["kill_share_step"]),
        fmt(dis["spread_seconds"]), fmt(dis["death_minutes"]), fmt(dis["mcdonalds_price"]),
        fmt(dis["calm_hours_min"]), fmt(dis["calm_hours_max"]), fmt(dis["vaccine_price"]),
        fmt(dis["vaccine_price_per_hen"])))
    para("Stan ogniska (outbreak_on, outbreak_left, outbreak_timer, outbreak_dead) i spokoj "
         "(disease_calm) ida do zapisu. Przy grze w tle zaraza staje, gdy straty plus chore "
         "dobija do loss_budget - po powrocie gracza ognisko rusza dalej.")

    head("6.4 Lis - maszyna stanow")
    block("""
   [BRAK LISA]
       |  co klatke: fox_roll_timer += krok (ZEGAR)
       |  karencja %s min ZEGARA i stado >= %s, inaczej czekaj
       |  odstep = active_roll_minutes (%s min)
       |           albo offline_roll_hours (%s h)
       |           * hand_return_factor (%s), gdy ostatni lis przegoniony
       |             PALCEM i ferma nie ma ani psa, ani plotu
       |           * fox_next_multiplier (%s po zagryzieniu, potem 1)
       v  minal odstep -> kostka: active_chance / offline_chance
   [KOSTKA UDANA]
       |  randf() < block_chance plotu ? -> zawraca (fox_blocked)
       v
   [WIZYTA]  lup = losowo kills_min..kills_max (%s..%s), nie wiecej niz stado
       |     licznik trafien = scare_taps (%s)
       |     PIERWSZA kura ginie od razu
       |     kolejne co losowe kill_interval_min..max (%s..%s s ZEGARA)
       |     kazda ofiara: zwloki z szansa carcass_share (%s), inaczej znika
       |
       |  konczy wizyte to, co nastapi pierwsze:
       |     - gracz trafil scare_taps razy     -> fox_scared (hand_scared)
       |     - pies: co interval s rzut chance;  -> fox_chased
       |       przy sukcesie rzut kill_chance    -> fox_killed (rozszarpany)
       |     - lup zebrany                       -> fox_left
       |     - minelo visit_max_minutes (%s)     -> fox_left
       v
   [BRAK LISA]   (Simulation._fox_leaves zeruje caly stan wizyty)

   RZEZ: przy wejsciu na ferme BEZ psa z szansa massacre_chance (%s)
   lup = cale stado, odstepy * massacre_pace_factor (%s), wizyta
   wydluzona tak, zeby zdazyl. Przegonienie palcem ja przerywa.""" % (
        fmt(fox["grace_minutes"]), fmt(fox["min_hens"]), fmt(fox["active_roll_minutes"]),
        fmt(fox["offline_roll_hours"]), fmt(fox["hand_return_factor"]),
        fmt(fox["killed_return_multiplier"]), fox["kills_min"], fox["kills_max"], fox["scare_taps"],
        fmt(fox["kill_interval_min"]), fmt(fox["kill_interval_max"]), fmt(fox["carcass_share"]),
        fmt(fox["visit_max_minutes"]), fmt(fox["massacre_chance"]), fmt(fox["massacre_pace_factor"])))
    para("Przy grze w tle ta sama wizyta jest rozgrywana natychmiast na osi czasu "
         "(_fox_visit_offline): kolejne zabojstwa i rzuty psa sa ukladane w kolejnosci ich czasow, "
         "wygrywa wczesniejsze zdarzenie. Nie ma tylko klikania.")
    para("Na raz moze byc tylko jeden lis. Scena lisa (scenes/farm/fox.gd) trzyma wlasny zegar "
         "zycia, ale zawsze slucha sygnalow fox_scared / fox_chased / fox_killed - bez tego "
         "skrocona wizyta zostawiala lisa na wybiegu (blad z 12.x: trzy niesmiertelne lisy).")

    head("6.5 Pies i plot")
    para("Plot i pies dzialaja niezaleznie. PLOT decyduje, czy lis w ogole wejdzie (block_chance). "
         "PIES skraca wizyte lisa, ktory juz wszedl. Pies stoi w FarmState.dog_level (0 = brak, "
         "1 = kundel, 2 = owczarek), plot w guard_level (0-4).")
    dogs = BAL["buildings"]["dog"]["upgrades"]
    table(["poziom", "pies", "cena", "rzut co", "szansa", "zagryza"],
          [[i + 1, d["name"], "%s zl" % d["price"], "%s s" % fmt(d["interval"]),
            "%.0f%%" % (d["chance"] * 100), "%.0f%%" % (d["kill_chance"] * 100)]
           for i, d in enumerate(dogs)], "rlrrrr")

    head("6.6 Inkubator i odchow")
    para("Game.incubate(rasa) zabiera eggs_per_chick (%s) jaja i zajmuje jedno miejsce na "
         "incubate_seconds rasy (s GRY). Wykluty pisklak rosnie przez grow_seconds i staje sie "
         "kura albo kogutem. Pisklę, dla ktorego brak miejsca w kurniku, czeka. Bez paszy oba "
         "liczniki stoja." % BAL["incubator"]["eggs_per_chick"])

    head("6.7 Wygrana")
    para("Simulation.check_win: pieniadze >= win.money (%s zl), a przy win.collection = true "
         "takze komplet ras. Wygrana ustawia state.won i pokazuje panel." % fmt(BAL["win"]["money"]))

    # ------------------------------------------------------------------ 7
    title("7. KONFIGURACJA - wszystkie zmienne")
    para("Cala liczbowa konfiguracja jest w data/balance.json i data/breeds.json. Kod nie ma "
         "wpisanych na sztywno cen ani czasow - zmiana liczby w pliku zmienia gre. Klucze "
         "zaczynajace sie od podkreslnika (\"_opis\") to komentarze; gra je pomija.")
    block("""
  JEDNOSTKI:   ZEGAR = czas rzeczywisty     GRA = czas gry (rozdzial 4)
               0-1   = prawdopodobienstwo (0.25 = 25%)
               zl, kg, szt., px - jak w nazwie""")
    para("Plik JSON nie znosi literowek: kazdy klucz w cudzyslowie, przecinek miedzy elementami, "
         "brak przecinka po ostatnim, kropka (nie przecinek) w liczbach dziesietnych. Zly plik = gra "
         "sie nie uruchomi - dlatego automat na GitHubie najpierw uruchamia testy i przy bledzie NIC "
         "nie wdraza.")
    section = None
    for key, value in leaves(BAL):
        top = key.split(".")[0]
        if top != section:
            section = top
            head("balance.json -> %s" % top)
        unit, desc, where = OPISY.get(key, ("?", "BRAK OPISU - uzupelnij tools/gen_dokumentacja.py", "?"))
        if L and L[-1].strip() and not L[-1].startswith("  --"):
            L.append("")
        L.append("  " + key)
        L.extend(wrap_into("= %s   [%s]" % (fmt(value), unit), "      "))
        L.extend(wrap_into(desc, "      "))
        L.extend(wrap_into("uzycie: " + where, "      "))

    head("breeds.json - pola kazdej rasy")
    for f, (unit, desc) in OPISY_RAS.items():
        L.append("")
        L.append("  %-18s [%s]" % (f, unit))
        L.extend(wrap_into(desc, "      "))
    head("breeds.json - aktualne wartosci")
    rows = []
    for b in BREEDS:
        rows.append([b["id"], b["price"], b["sell_price"], fmt(b["egg_value"]), fmt(b["egg_seconds"]),
                     fmt(b["incubate_seconds"]), fmt(b["grow_seconds"]), b.get("coop_level", 0)])
    table(["id", "price", "sell", "egg_val", "egg_s", "incub_s", "grow_s", "lvl"], rows, "lrrrrrrr")
    para("Czasy w tej tabeli sa w sekundach GRY. Na zegar: pomnoz przez %g." % round(1 / SCALE, 4))

    head("buildings.json")
    para("Lista budynkow stojacych na fermie: id (coop, incubator, storage, shop) i klucze tekstow "
         "nazwy i opisu. Liczby budynkow sa w balance.json -> buildings i incubator. Wyglad "
         "budynku zmienia sie na poziomach 3 i 6 (scenes/farm/farm.gd: LOOK_STEPS, grafiki "
         "z tools/gen_buildings.py).")

    head("strings.csv")
    para("Wszystkie teksty gry: kolumna keys (klucz) i pl (tekst). Tekst z %s albo %d to szablon "
         "- liczbe wstawia kod. Po zmianie tego pliku Godot musi przeliczyc tlumaczenie: "
         "godot --headless --path . --import (automat robi to sam). Bez tego gra pokazuje stare "
         "teksty.")

    head("backend.json")
    block("""
  enabled           %s       false = gra tylko lokalnie, bez serwera
  url               %s
  api_key           sb_publishable_...  klucz PUBLIKOWALNY (rozdzial 10)
  table             %s
  timeout_seconds   %s""" % (fmt(BACKEND.get("enabled")), BACKEND.get("url"), BACKEND.get("table"),
                            BACKEND.get("timeout_seconds")))

    # ------------------------------------------------------------------ 8
    title("8. Model danych")
    head("FarmState (core/model/farm_state.gd) - najwazniejsze pola")
    block("""
  money                 float   pieniadze (zl z groszami)
  feed                  float   pasza (kg)
  eggs                  {rasa: szt.}       jaja w magazynie
  egg_ages              {rasa: [wiek s]}   wiek jaj do gnicia (ZEGAR)
  eggs_on_ground        {rasa: szt.}       jaja na trawie
  chickens              [Chicken]          dorosle ptaki (kury i koguty)
  incubating            [{breed, elapsed}] partie w inkubatorze
  chicks                [{breed, grown}]   piskleta
  corpses               [Corpse]           zwloki na wybiegu
  unlocked_breeds       [rasa]             rasy juz posiadane
  coop_level / storage_level / incubator_level / guard_level / dog_level
  fox_visit_left        s ZEGARA do konca wizyty (0 = brak lisa)
  fox_kill_left         ile kur lis jeszcze zabierze
  fox_kill_timer        s do nastepnej ofiary
  fox_taps_left         ile trafien do przegonienia
  fox_roll_timer        s od ostatniej kostki
  fox_hand_scared       ostatni lis przegoniony palcem
  fox_next_multiplier   mnoznik odstepu po zagryzieniu
  dog_timer             s do nastepnego rzutu psa
  disease_timer         s od ostatniej kostki choroby
  hunger_seconds        s GRY bez paszy
  rooster_hints         {rasa: ile razy pokazano "brak koguta"} (max 3)
  intro_seen            gracz przeszedl ekran powitalny
  won / win_reason      wygrana""")
    head("Chicken (core/model/chicken.gd)")
    block("""
  breed_id, is_rooster, since_last_egg (s GRY), sick, sick_seconds (s GRY),
  vaccinated""")
    head("Sygnaly (services/events.gd)")
    for s in signals():
        L.append("  " + s)

    # ------------------------------------------------------------------ 9
    title("9. Zapis gry - format i migracje")
    para("Zapis to jeden dokument JSON (SaveGame.to_dict). Lokalnie lezy w user://save.json - w "
         "przegladarce Godot mapuje user:// na IndexedDB strony. Ten sam dokument jedzie na serwer "
         "jako pole payload. Aktualna wersja formatu: %s (SaveGame.VERSION)." % save_version())
    block("""
  {
    "version": %s,                 wersja FORMATU (nie gry)
    "saved_at": 1795508306.0,     ostatnia POLICZONA chwila (unix, ZEGAR)
    "money": 1431.0, "feed": 1040.0, "days": 12, "day_fraction": 0.4,
    "eggs": {"leghorn": 40}, "egg_ages": {"leghorn": [...]},
    "eggs_on_ground": {...}, "unlocked": ["leghorn", ...],
    "chickens": [{"breed": "leghorn", "rooster": false, "sick": false,
                  "vaccinated": true, ...}, ...],
    "incubating": [...], "chicks": [...], "corpses": [...],
    "coop_level": 2, "storage_level": 1, "incubator_level": 1,
    "guard_level": 1, "dog_level": 1,
    "fox_*", "disease_timer", "hunger_seconds", "rooster_hints",
    "intro_seen": true, "won": false, ...
  }""" % save_version())
    para("Migracje (SaveGame._migrate) podnosza stary zapis krok po kroku do aktualnej wersji: "
         "1 -> 2 inkubator, piskleta, dni; 2 -> 3 jaja wedlug rasy, choroby, glod, lis; 3 -> 4 "
         "poziomy budynkow; 4 -> 5 koguty (kazda rasa dostaje jednego w prezencie); 5 -> 6 obrona "
         "rozbita na plot i psa (stary poziom 0-5 przeliczony hojnie na pare plot+pies).")
    para("ZASADA: dodajesz pole do zapisu -> czytaj je w from_dict z wartoscia domyslna. Zmieniasz "
         "znaczenie istniejacego pola -> podnies SaveGame.VERSION i dopisz krok w _migrate. Zapisy "
         "graczy nie moga przestac sie wczytywac.")

    # ------------------------------------------------------------------ 10
    title("10. Serwer: Supabase od podstaw")
    head("Co to jest")
    para("Supabase to uslugowa baza PostgreSQL z gotowym interfejsem REST. Postgres to zwykla baza "
         "SQL: dane sa w tabelach, tabela ma kolumny o stalych typach, wiersze to rekordy. Supabase "
         "dodaje do niej PostgREST - program, ktory kazda tabele wystawia pod adresem HTTP. Dzieki "
         "temu gra nie potrzebuje wlasnego serwera: wysyla zwykle zapytania HTTPS prosto do bazy.")
    block("""
  projekt:  %s
  tabela:   public.%s
  panel:    https://supabase.com/dashboard -> projekt -> Table Editor""" % (BACKEND.get("url"), BACKEND.get("table")))
    head("Tabela saves")
    block("""
  kolumna      typ      znaczenie
  -----------  -------  --------------------------------------------------
  player_id    text     KOD FERMY, 6 cyfr. PRIMARY KEY = unikalny; jeden
                        wiersz na ferme. Po nim baza wie, ktory wiersz
                        nadpisac przy zapisie.
  payload      jsonb    caly zapis gry (rozdzial 9). jsonb = JSON
                        przechowywany binarnie; da sie po nim szukac SQL.
  updated_at   bigint   czas ostatniego zapisu, unix (sekundy). MUSI byc
                        bigint - gra wysyla liczbe, kolumna timestamptz
                        odrzucilaby zapis kodem 400.""")
    para("Pelna definicja tabeli i polityk: docs/supabase.sql (wklejana w Supabase -> SQL Editor -> "
         "Run).")
    head("Klucze i bezpieczenstwo (RLS)")
    para("Supabase daje dwa rodzaje kluczy. Klucz PUBLIKOWALNY (sb_publishable_..., dawniej anon) "
         "jest przeznaczony do siedzenia w aplikacji u gracza - jest w data/backend.json i w kazdej "
         "kopii gry. Klucz SEKRETNY (sb_secret_..., dawniej service_role) omija wszystkie "
         "zabezpieczenia i NIGDY nie moze trafic do repozytorium ani do gry.")
    para("Co wolno kluczowi publikowalnemu, decyduje RLS (Row Level Security) - reguly zapisane "
         "w bazie przy tabeli. Bez zadnej polityki tabela jest dla niego zamknieta: odczyt zwraca "
         "pusta liste, zapis konczy sie 401/403. Tabela saves ma trzy polityki dla roli anon: "
         "SELECT using (true), INSERT with check (true), UPDATE using (true). DELETE nie ma "
         "- przez API nie da sie skasowac fermy.")
    para("W praktyce znaczy to: KAZDY, kto ma klucz z gry, moze przeczytac WSZYSTKIE fermy i "
         "nadpisac dowolna z nich. To swiadomy kompromis (gra bez logowania, kod fermy jako "
         "jedyny identyfikator). Ochrona przed utrata danych to codzienne kopie (rozdzial 13). "
         "Uwaga: komentarz w tools/supabase_setup.sql twierdzil kiedys, ze polityki nie pozwalaja "
         "listowac cudzych farm - to nieprawda, using (true) pozwala.")
    head("Zapytania, ktore wysyla gra (services/cloud.gd)")
    block("""
  Naglowki przy kazdym zapytaniu:
    apikey: <klucz>
    Authorization: Bearer <klucz>
    Content-Type: application/json

  ODCZYT jednej fermy (Cloud.pull / pull_for):
    GET  <url>/rest/v1/saves?player_id=eq.130090&select=payload,updated_at
    -> 200 i  [ {"payload": {...}, "updated_at": 1795...} ]   ferma jest
    -> 200 i  []                                              nie ma takiej

  ZAPIS (Cloud.push) - "upsert": wstaw, a jesli kod istnieje, nadpisz:
    POST <url>/rest/v1/saves?on_conflict=player_id
    Prefer: resolution=merge-duplicates,return=minimal
    body: [ {"player_id": "130090", "payload": {...},
             "updated_at": 1795508306} ]
    -> 201 albo 204 = zapisane""")
    head("To samo z wiersza polecen (curl)")
    block("""
  URL=%s
  KEY=$(python3 -c "import json;print(json.load(
        open('data/backend.json'))['api_key'])")

  # jedna ferma
  curl -s "$URL/rest/v1/saves?player_id=eq.130090&select=payload" \\
       -H "apikey: $KEY" -H "Authorization: Bearer $KEY"

  # lista wszystkich kodow z data zapisu
  curl -s "$URL/rest/v1/saves?select=player_id,updated_at" \\
       -H "apikey: $KEY" -H "Authorization: Bearer $KEY\"""" % BACKEND.get("url"))
    head("Przydatne SQL (Supabase -> SQL Editor)")
    block("""
  -- fermy od najbogatszej, z liczba ptakow i data zapisu
  select player_id,
         (payload->>'money')::numeric            as kasa,
         jsonb_array_length(payload->'chickens') as ptaki,
         to_timestamp(updated_at)                as zapisano
  from saves order by kasa desc;

  -- jedna ferma w calosci
  select payload from saves where player_id = '130090';

  -- reczna zmiana pieniedzy na fermie (NADPISUJE stan gracza!)
  update saves
     set payload = jsonb_set(payload, '{money}', '5000'::jsonb)
   where player_id = '130090';""")
    para("Operator ->> wyciaga pole JSON jako tekst, -> jako JSON; jsonb_set podmienia jedno pole. "
         "Uwaga przy recznej edycji: otwarta u gracza gra przy nastepnym autozapisie nadpisze zmiane "
         "swoim stanem. Gracz musi miec zamknieta gre, a po zmianie wczytac ferme kodem.")
    head("Darmowy plan i keepalive")
    para("Darmowy projekt Supabase jest wstrzymywany po tygodniu bez ruchu. Workflow "
         "supabase-keepalive.yml raz dziennie robi jedno zapytanie, zeby do tego nie doszlo. "
         "Wstrzymany projekt wznawia sie recznie w panelu Supabase - dane nie gina.")
    head("Odtwarzanie fermy z kopii")
    block("""
  kopie/saves-RRRR-MM-DD.json = lista wierszy {player_id, payload, updated_at}

  python3 - <<'PY'
  import json
  rows = json.load(open("kopie/saves-2026-11-24.json"))
  row = [r for r in rows if r["player_id"] == "666478"][0]
  json.dump([row], open("/tmp/przywroc.json", "w"))
  PY
  curl -s -X POST "$URL/rest/v1/saves?on_conflict=player_id" \\
       -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \\
       -H "Content-Type: application/json" \\
       -H "Prefer: resolution=merge-duplicates,return=minimal" \\
       --data @/tmp/przywroc.json""")
    para("Gracz musi miec zamknieta gre, a potem wczytac ferme kodem. Z tego srodowiska (Claude) "
         "adres supabase.co jest zablokowany - takie operacje robi sie z wlasnego komputera albo "
         "przez workflow GitHub Actions.")

    # ------------------------------------------------------------------ 11
    title("11. Synchronizacja z serwerem")
    head("Kiedy gra wysyla stan (Game.save -> Cloud.push)")
    block("""
  - autozapis co %s s ZEGARA (odliczany zegarem, nie klatkami)
  - odejscie od karty / okna (FOCUS_OUT) - natychmiast
  - zamkniecie gry, pauza aplikacji, wyjscie ze sceny
  - po kazdym wczytaniu fermy z serwera
  - przed przeladowaniem przy aktualizacji (Updater)""" % _autosave())
    head("Kiedy NIE wysyla (Game.may_push_to_cloud - cztery bezpieczniki)")
    block("""
  1. trwa wczytywanie fermy po kodzie (_force_pull) - lokalny stan jest
     jeszcze stary i nadpisalby ferme, na ktora gracz czeka
  2. kod urzadzenia (Cloud.player_id) nie jest kodem, ktory ta sesja
     faktycznie zdobyla (_owned_code) - np. po nieudanym wczytaniu
  3. gracz nie przeszedl ekranu powitalnego (intro_seen = false) -
     swieza ferma po wyczyszczeniu przegladarki nie leci na serwer,
     zanim gracz wybierze "Nowa ferma" albo wpisze kod
  4. ferma jest pusta (zero ptakow, zero pieniedzy...) - pusta ferma
     nigdy nie nadpisze prawdziwej""")
    head("Zasady scalania przy odczycie (Game._on_cloud_pulled)")
    block("""
  start gry (Cloud.pull):     serwer wygrywa TYLKO gdy jego saved_at jest
                              nowszy niz lokalnego zapisu
  wpisany kod (restore):      serwer wygrywa ZAWSZE; dopiero po udanej
                              odpowiedzi urzadzenie przyjmuje ten kod
  brak fermy / brak sieci:    komunikat, stan lokalny bez zmian""")
    para("Kod fermy: 6 cyfr, losowany przy \"Nowa ferma\" (Cloud.new_player_id, %d..%d), "
         "trzymany w user://player_id.txt. Wyczyszczenie danych strony kasuje go - dlatego gracz "
         "musi zapisac kod. Zakres przyjmuje tez stare 12-znakowe kody (LEGACY_*)." % (100000, 999999))

    # ------------------------------------------------------------------ 12
    title("12. Budowanie, wdrazanie, aktualizacje w otwartych kartach")
    head("tools/build_web.sh <katalog>")
    block("""
  1. godot --export-release "Web"   -> index.html, index.js, index.wasm,
                                       index.pck, ikony, worklety audio
  2. index.wasm (~40 MB) -> gzip -> engine-<wersja Godota>.txt (~10 MB)
     GitHub Pages przyjmuje pliki do 20 MB i serwuje .txt; plik
     rozpakowuje w przegladarce tools/web/wasm_gz_loader.js
  3. index.pck -> pack-<wersja gry>.txt, wskazany w index.html (mainPack)
  4. skrypty dostaja ?v=<wersja> w adresie
  5. version.json  {"version": "<wersja gry>"}
  6. kazda podmiana jest sprawdzana grepem - brak = build przerwany""")
    para("Nazwy z numerem wersji sa po to, zeby przegladarka nie podala starej gry z pamieci "
         "podrecznej. Silnik ma w nazwie wersje GODOTA, wiec 10 MB pobiera sie tylko przy zmianie "
         "silnika.")
    head("tools/deploy_pages.sh <katalog>")
    para("Klonuje galaz gh-pages, podmienia pliki, zostawia TRZY ostatnie pack-*.txt (index.html "
         "z pamieci podrecznej sprzed kilku minut musi dalej znalezc swoj pakiet), commit, push. "
         "Zmienne: DEPLOY_REMOTE (adres repo z tokenem w Actions), DEPLOY_AUTHOR.")
    head("Aktualizacja w otwartej karcie (services/updater.gd)")
    block("""
  co 60 s ZEGARA i przy powrocie do karty:
     GET version.json?t=<teraz>
     inna wersja niz GameData.VERSION?
        -> zapis fermy + czekanie na serwer (max 5 s)
        -> 1,5 s na zapis w IndexedDB przegladarki
        -> znacznik w localStorage "kury_update" {to, attempts, at}
        -> location.replace(index.html?v=<nowa>)
  po przeladowaniu: znacznik swiezy i wersja sie zgadza
        -> brak ekranu z kodem, komunikat "zaktualizowano"
  bezpiecznik: 2 nieudane proby tej samej wersji -> prosba o reczne
     odswiezenie zamiast petli przeladowan""")
    para("Cofniecie wersji (reset galezi gh-pages na starszy commit) tez dociera do otwartych kart "
         "- updater reaguje na kazda roznice numeru, w gore i w dol.")
    head("Numer wersji")
    para("Bazowy numer siedzi w DWOCH miejscach i musza byc rowne: project.godot "
         "(config/version) i core/util/game_data.gd (VERSION). Automat na GitHubie dokleja do niego "
         "numer przebiegu (np. 12.15 -> 12.15.37) tylko w kopii do budowania - dzieki temu KAZDE "
         "wdrozenie ma inna wersje i otwarte karty zawsze je zauwaza, takze gdy zmieniles sama "
         "cene bez podbijania numeru.")

    # ------------------------------------------------------------------ 13
    title("13. GitHub Actions")
    for plik, nazwa, kiedy in workflows():
        L.append("")
        L.append("  " + plik)
        L.append("      " + nazwa)
        L.append("      uruchamia sie: " + kiedy)
    head("buduj-i-wdroz.yml - kroki")
    block("""
  1. pobierz Godota 4.7.2 i szablon web_nothreads (pamiec podreczna
     Actions - pobiera sie raz, potem z cache)
  2. godot --import            (tlumaczenia z strings.csv)
  3. gen_instrukcja.py, gen_dokumentacja.py --check-keys
  4. testy logiki              -> musi byc "0 BLEDOW"
  5. test dymny (xvfb + opengl3) -> musi byc "TEST DYMNY: OK"
  6. przegenerowane INSTRUKCJA/DOKUMENTACJA -> commit na main
  7. numer wersji + numer przebiegu -> build_web.sh -> deploy_pages.sh
  Ktorykolwiek krok sie wysypie = NIC nie trafia do graczy.""")
    para("Nie uruchamia sie przy zmianach w kopie/, w plikach .md/.TXT ani w samych "
         "wygenerowanych dokumentach - codzienna kopia farm nie wdraza gry. Wynik: zakladka "
         "Actions w repozytorium na GitHubie.")
    head("Pozostale")
    para("kopia-farm.yml - codziennie zrzuca cala tabele saves do kopie/saves-RRRR-MM-DD.json "
         "i commituje. sprawdz-ferme.yml - recznie, podajesz kod, dostajesz podsumowanie fermy "
         "i liste wszystkich farm. supabase-keepalive.yml - codzienne zapytanie podtrzymujace "
         "darmowy projekt. Wszystkie biora adres i klucz z data/backend.json.")

    # ------------------------------------------------------------------ 14
    title("14. Testy i reguly pilnowane w konfiguracji")
    block("""
  testy logiki:  godot --headless --path . --quit-after 2000 tests/tests.tscn
                 ostatnia linia: "TESTY: N OK, 0 BLEDOW"
  test dymny:    xvfb-run -a godot --path . --rendering-driver opengl3 \\
                     --quit-after 40000 tests/smoke_ui.tscn \\
                     [-- katalog_na_zrzuty]
                 ostatnia linia: "TEST DYMNY: OK\"""")
    para("Testy logiki (~1300 sprawdzen) uruchamiaja core/ bez grafiki: zakupy, symulacje, lis, "
         "psy, choroby, glod, zapis i migracje, bezpieczniki synchronizacji, updater. Test dymny "
         "uruchamia cala gre z grafika, klika przyciski, wywoluje lisa i robi zrzuty ekranu.")
    head("Testy nie dotykaja bazy produkcyjnej (od 12.17)")
    para("Oba zestawy testow na starcie wolaja Cloud.use_test_server(), ktore podmienia adres "
         "Supabase na http://127.0.0.1:9 (nic tam nie slucha, kazde zapytanie od razu sie nie udaje), "
         "i sprawdzaja Cloud.is_test_server(). Workflow ustawia dodatkowo zmienna KURY_BEZ_SERWERA=1, "
         "ktora robi to samo juz w _ready() autoloadu Cloud. Przed 12.17 testy w CI pisaly do "
         "prawdziwej bazy - zostaly po tym fermy 399975 i 439267 (smieci) i zmieniona ferma 327733.")
    para("tests/bot_24h.tscn to tez pomiar: bot gra pierwsza dobe nowej fermy na prawdziwej logice "
         "(Simulation.advance + akcje Game) w trzech stylach - zaangazowany (sesja co 1,5 h), niedzielny "
         "(5 sesji) i maniak (16 h). Po \"--\" mozna podac katalog z innymi balance.json/breeds.json, "
         "zeby porownac dwie ekonomie. Wynik: wartosc fermy co godzine, przychody, pasza, straty, "
         "godzina pierwszego zakupu kazdego ulepszenia.")
    para("tests/fox_lab.tscn to nie test, tylko pomiar: 60 prob po 24 h na kilku fermach (bez "
         "obrony, plot, owczarek, oba), dwa style gry. Wypisuje pierwszego lisa, lisy na dobe, "
         "kury na lisa i na dobe. Trwa okolo 12 minut, nie jest uruchamiany w CI.")
    head("Reguly konfiguracji, ktore zatrzymaja wdrozenie")
    para("Od wersji 12.15 testy NIE trzymaja konkretnych cen ani czasow - mozna je zmieniac. "
         "Pilnuja tylko, zeby konfiguracja miala sens:")
    block("""
  - kazda rasa: price > sell_price > 0, 0 < egg_value < price
  - economy.rooster_price_multiplier miedzy 1 a 20
  - plot: dokladnie 4 poziomy (tyle jest grafik), kazdy drozszy
    i nie slabszy od poprzedniego, block_chance w (0, 1]
  - psy: dokladnie 2 (kundel, owczarek - tyle jest grafik); interval > 0,
    chance i kill_chance w [0, 1]; owczarek drozszy i w niczym nie
    gorszy od kundla; kundel nie drozszy niz pierwszy plot
  - lis: odstepy kostek > 0, szanse w [0, 1],
    kills_min >= 1, kills_max >= kills_min,
    kill_interval_min > 0, kill_interval_max >= kill_interval_min,
    killed_return_multiplier >= 1
  - egg_spoil_hours > 0, magazyn na poziomie 0 > 50 jaj
  - magazyn: z kazdym poziomem wiekszy worek, wiekszy rabat
    (pack_discount < 0.95) i tanszy kilogram paszy
  - choroba: zaraza co minute, 30-100% stada co 10%, 3-12 h spokoju
  - skup, szczepienie: cena > 0; leku nie ma
  - KAZDY klucz balance.json i breeds.json ma opis w tym dokumencie""")

    # ------------------------------------------------------------------ 15
    title("15. Narzedzia w tools/")
    block("""
  build_web.sh          budowa wersji przegladarkowej (rozdzial 12)
  deploy_pages.sh       wdrozenie na GitHub Pages (rozdzial 12)
  web/wasm_gz_loader.js rozpakowuje silnik w przegladarce
  gen_instrukcja.py     INSTRUKCJA.txt z danych gry
  gen_dokumentacja.py   ten dokument
  gen_buildings.py      warianty grafik budynkow na poziomy 3 i 6
  gen_fence.py          grafiki plotu, poziomy 1-4
  gen_roosters.py       grafiki kogutow
  gen_ground.py         tlo / trawa
  pastel_pass.py        ujednolicenie palety grafik
  economy_model.py      model ekonomii: jajka + hodowla, tempo rozbudowy
  upgrade_pacing.py     starszy model tempa (tylko jajka)
  balance_model.py      wczesny model balansu
  mock_backend.py       udawany Supabase do testow (np. odpowiedzi gzip)
  supabase_setup.sql    starsza wersja definicji tabeli; aktualna:
                        docs/supabase.sql""")

    # ------------------------------------------------------------------ 16
    title("16. Przepisy: typowe zmiany krok po kroku")
    head("Zmiana ceny / czasu / szansy - przez przegladarke, bez instalowania niczego")
    block("""
  1. https://github.com/sodorn/kury/blob/main/data/balance.json
     (albo data/breeds.json dla ras)
  2. ikona olowka "Edit this file" (prawy gorny rog podgladu pliku)
  3. zmien liczbe. Nie ruszaj cudzyslowow, przecinkow, nawiasow.
  4. "Commit changes..." -> opis zmiany -> "Commit changes"
  5. zakladka Actions: przebieg "Buduj i wdroz gre" (~5-8 min)
       zielony  -> gra wdrozona; otwarte karty przejda na nia same
                   w ciagu minuty
       czerwony -> nic nie wdrozono. Kliknij przebieg -> krok,
                   ktory sie wysypal; linie "BLAD: ..." mowia, co nie
                   pasuje (np. "plot 3 drozszy od poprzedniego").
                   Popraw plik tak samo (krok 1-4).""")
    head("To samo z wlasnego komputera")
    block("""
  git pull
  (edycja data/balance.json)
  git commit -am "Psy drozsze"
  git push""")
    para("Przed pushem warto zrobic git pull: automat sam dopisuje na main przegenerowane "
         "dokumenty, wiec lokalna kopia moze byc o commit w tyle.")
    head("Nowa rasa")
    block("""
  1. data/breeds.json - nowy wpis (wszystkie pola z rozdzialu 7, nowe id)
  2. data/strings.csv - klucze name, desc, lore
  3. grafiki: assets/sprites/animals/hen_*.svg, rooster_*.svg,
     zdjecie assets/photos/<id>.jpg
  4. testy maja na sztywno liczbe ras (17) i opis rasy w sklepie -
     do poprawy w tests/run_tests.gd""")
    head("Nowy poziom budynku")
    para("Dopisz element do listy upgrades w balance.json (te same pola co pozostale). Kurnik, "
         "magazyn, inkubator - dowolna liczba poziomow. Plot i pies - nie, bo maja grafike na "
         "kazdy poziom.")
    head("Nowe pole w zapisie gry")
    para("FarmState: nowe pole z wartoscia domyslna. SaveGame.to_dict: zapisz. SaveGame.from_dict: "
         "odczytaj z domyslna (stare zapisy go nie maja). Jesli zmieniasz znaczenie starego pola: "
         "SaveGame.VERSION + 1 i krok w _migrate. Test w run_tests.gd: zapis -> odczyt -> to samo.")
    head("Nowy tekst")
    para("Wiersz w data/strings.csv (KLUCZ,\"tekst\"), w kodzie tr(\"KLUCZ\"). Potem import "
         "(automat robi sam).")
    head("Nowa wersja Godota")
    para("Zmien 4.7.2 w .github/workflows/buduj-i-wdroz.yml (zmienna GODOT_VERSION i klucz cache). "
         "Silnik dostanie nowa nazwe pliku sam (build_web.sh czyta wersje z godot --version).")

    # ------------------------------------------------------------------ 17
    title("17. Znane ryzyka i ograniczenia")
    block("""
  - Kazdy z kluczem z gry moze czytac i nadpisac kazda ferme (RLS
    using(true)). Ochrona: codzienne kopie w kopie/.
  - Kod fermy jest losowany bez sprawdzania, czy juz istnieje. Przy N
    fermach szansa trafienia w cudzy kod przy nowej fermie = N/900000
    (20 farm -> 0,002%%). Trafienie nadpisaloby cudza ferme.
  - Wyczyszczenie danych strony kasuje kod z urzadzenia. Bez zapisanego
    kodu fermy nie da sie odnalezc z poziomu gry (jest na serwerze;
    da sie ja znalezc przez sprawdz-ferme.yml albo SQL).
  - Kopie robia sie raz dziennie. Stan miedzy kopiami jest tylko
    w ostatnim zapisie na serwerze.
  - Gra liczy wszystko u gracza. Zmodyfikowana gra moze wyslac dowolny
    stan - serwer niczego nie sprawdza.
  - Karta w tle: przegladarki zamrazaja strone. Czas sie nie gubi
    (rozdzial 4), ale przez zamrozenie nic nie idzie na serwer, wiec
    serwer ma stan z chwili odejscia od karty.
  - Darmowy Supabase: wstrzymanie po tygodniu bez ruchu (keepalive),
    limity miejsca i ruchu planu darmowego.""")
    raw("")
    rule("=")
    raw("  koniec dokumentu  *  wygenerowano z wersji %s" % v)
    rule("=")
    return "\n".join(L) + "\n"


def _const(name):
    m = re.search(r"const %s := ([0-9.]+)" % name, (ROOT / "services" / "game.gd").read_text(encoding="utf-8"))
    return m.group(1) if m else "?"


def _autosave():
    m = re.search(r"const AUTOSAVE_SECONDS := ([0-9.]+)", (ROOT / "services" / "game.gd").read_text(encoding="utf-8"))
    return m.group(1) if m else "?"


if __name__ == "__main__":
    args = sys.argv[1:]
    missing, dead = check_keys()
    bad = False
    if missing:
        print("BLAD: klucze bez opisu w tools/gen_dokumentacja.py (OPISY / OPISY_RAS):")
        for k in missing:
            print("   ", k)
        bad = True
    if dead:
        print("BLAD: opisy kluczy, ktorych nie ma juz w konfiguracji:")
        for k in dead:
            print("   ", k)
        bad = True
    text = build()
    too_long = [i + 1 for i, line in enumerate(text.splitlines()) if len(line) > W]
    if too_long:
        print("BLAD: wiersze dluzsze niz %d znakow: %s" % (W, too_long[:10]))
        bad = True
    if "--check-keys" in args:
        sys.exit(1 if bad else 0)
    if "--check" in args:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            print("BLAD: DOKUMENTACJA_TECHNICZNA.txt jest nieaktualna - uruchom tools/gen_dokumentacja.py")
            bad = True
        sys.exit(1 if bad else 0)
    if bad:
        sys.exit(1)
    OUT.write_text(text, encoding="utf-8")
    print("zapisano %s (%d wierszy)" % (OUT.name, len(text.splitlines())))
