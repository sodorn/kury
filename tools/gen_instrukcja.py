#!/usr/bin/env python3
"""Sklada INSTRUKCJA.txt z prawdziwych danych gry.

Instrukcja pisana recznie rozjedzie sie z gra przy pierwszej zmianie ceny.
Dlatego wszystkie liczby - ceny, pojemnosci, czasy, tabela ras - sa czytane
z `data/balance.json`, `data/breeds.json` i `data/strings.csv`. Tekst
opisowy siedzi tutaj, w tym pliku.

Po KAZDEJ zmianie balansu:

    python3 -I tools/gen_instrukcja.py

Sprawdza to test `_test_instrukcja_aktualna` - jesli zapomnisz, testy
zapala sie na czerwono.
"""

import csv
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import dane  # noqa: E402  (poziomy budynkow z data/rozbudowy.json)

BAL = dane.load_balance()
BREEDS = json.loads((ROOT / "data" / "breeds.json").read_text(encoding="utf-8"))
if isinstance(BREEDS, dict):
    BREEDS = BREEDS["breeds"]

W = 78  # szerokosc ramki


def strings() -> dict:
    out = {}
    with (ROOT / "data" / "strings.csv").open(encoding="utf-8", newline="") as fh:
        for row in csv.reader(fh):
            if len(row) >= 2:
                out[row[0]] = row[1]
    return out


S = strings()
L = []


def raw(text: str = "") -> None:
    L.append(text)


def rule(ch: str = "=") -> None:
    L.append(ch * W)


def box(lines: list, indent: str = "  ") -> None:
    """Ramka o stalej szerokosci. Padding liczony, nie klepany recznie."""
    inner = W - len(indent) - 4
    L.append("")
    L.append(indent + "+" + "-" * (inner + 2) + "+")
    for text in lines:
        L.append(indent + "|  " + text.ljust(inner) + "|")
    L.append(indent + "+" + "-" * (inner + 2) + "+")


def title(text: str) -> None:
    if L and L[-1].strip():
        L.append("")
    rule("=")
    L.append(" " + text.upper())
    rule("=")


def head(text: str) -> None:
    L.append("")
    L.append("  " + text)
    L.append("  " + "-" * (W - 4))


def para(text: str, indent: str = "  ") -> None:
    """Lamie akapit na szerokosc ramki, bez rozwalania slow.

    Akapity rozdziela PUSTA LINIA. Pojedyncze zlamanie wiersza w zrodle to
    tylko wygoda pisania — tekst i tak sklada sie od nowa.
    """
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


def table(headers: list, rows: list, align: str = "") -> None:
    """Prosta tabela ASCII. `align` to ciag 'l'/'r' dla kolejnych kolumn."""
    cols = len(headers)
    align = (align + "l" * cols)[:cols]
    widths = [len(str(h)) for h in headers]
    for r in rows:
        for i, cell in enumerate(r):
            widths[i] = max(widths[i], len(str(cell)))
    def line(ch="-", cross="+"):
        return "  " + cross + cross.join(ch * (w + 2) for w in widths) + cross
    def row(cells):
        out = []
        for i, cell in enumerate(cells):
            text = str(cell)
            out.append(" " + (text.rjust(widths[i]) if align[i] == "r" else text.ljust(widths[i])) + " ")
        return "  |" + "|".join(out) + "|"
    if L and L[-1].strip():
        L.append("")
    L.append(line("="))
    L.append(row(headers))
    L.append(line("="))
    for r in rows:
        L.append(row(r))
    L.append(line("-"))


def zl(value) -> str:
    value = float(value)
    whole = int(round(value)) if abs(value - round(value)) < 0.005 else value
    if isinstance(whole, int):
        return "{:,}".format(whole).replace(",", " ") + " zl"
    return ("%.2f" % value).replace(".", ",") + " zl"


def gr(value) -> str:
    """Cena jajka zawsze z groszami, zeby kolumna byla rowna."""
    return ("%.2f" % float(value)).replace(".", ",") + " zl"


def num(value) -> str:
    return "{:,}".format(int(value)).replace(",", " ")


def real_seconds(game_seconds: float) -> float:
    """Sekundy przy zegarku z sekund gry. Gra chodzi `scale` razy wolniej."""
    return float(game_seconds) / SCALE


def czas_krotki(seconds: float) -> str:
    """Zwiezly czas do tabeli: 12s, 7m30, 1h02."""
    seconds = int(round(float(seconds)))
    if seconds < 60:
        return "%ds" % seconds
    if seconds < 3600:
        return "%dm%02d" % (seconds // 60, seconds % 60)
    return "%dh%02d" % (seconds // 3600, (seconds % 3600) // 60)


def czas(seconds: float) -> str:
    seconds = round(float(seconds))
    if seconds < 60:
        return "%d s" % seconds
    if seconds < 3600:
        return "%d min %02d s" % (seconds // 60, seconds % 60)
    return "%d h %02d min" % (seconds // 3600, (seconds % 3600) // 60)


SCALE = float(BAL["offline"]["scale"])
ECO = BAL["economy"]

# --------------------------------------------------------------------------

rule("=")
raw("""
   ####  #   # #   # #   # #     #####  ##### #####  ####
  #      #  #  #   # ##  # #       #    #     #   #  #   #
   ###   ###   #   # # # # #       #    ###   #####  ####
      #  #  #  #   # #  ## #       #    #     #  #   #   #
  ####   #   #  ###  #   # #####   #    ##### #   #  ####

           S Y M U L A T O R   H O D O W L I   K U R C Z A K O W
""".rstrip("\n"))
rule("=")
raw("")
def wersja() -> str:
    for line in (ROOT / "project.godot").read_text(encoding="utf-8").splitlines():
        if line.startswith("config/version="):
            return line.split("=", 1)[1].strip().strip('"')
    return "?"


para("INSTRUKCJA OBSLUGI  ***  gra w wersji %s" % wersja())
para("Gra dziala w przegladarce: https://sodorn.github.io/kury/")
para("Plik generowany automatycznie przez tools/gen_instrukcja.py - nie poprawiaj go recznie, bo kolejne uruchomienie skryptu nadpisze zmiany.")
raw("")

title("1. O CO CHODZI W TEJ GRZE")
para("""
Prowadzisz hodowle kur. Kury znosza jaja, jaja sprzedajesz albo wkladasz do
inkubatora. Z jaj wykluwaja sie pisklęta, pisklęta rosna i staja sie doroslymi
kurami, ktore mozesz sprzedac drozej, niz kosztowalo ich wyhodowanie.
""")
para("""
Jest siedemnascie ras. Im drozsza rasa, tym drozsze jaja i tym wiecej dostaniesz
za dorosla sztuke - ale tym dluzej trwa odchow i tym czesciej taka kura choruje.
""")
para("""
Przeszkody sa trzy: PASZA (kosztuje i konczy sie sama), CHOROBA (przechodzi
z kury na kure co minute i nie ma na nia leku) i LIS (wchodzi na wybieg
i zabija kury jedna po drugiej, a bez psa potrafi wybic cale stado).
""")
para("CEL: uzbierac %s." % zl(BAL["win"]["money"]))

title("2. PIERWSZE URUCHOMIENIE I KOD FERMY")
para("""
Przy wejsciu do gry zobaczysz ekran powitalny. Sa na nim dwie drogi:
""")
raw("""
    NOWA FERMA        - zaklada swieze gospodarstwo i nadaje mu nowy kod.
    WCZYTAJ Z KODU    - wpisujesz szesciocyfrowy kod i wracasz na swoja ferme.
""".rstrip("\n"))
box([
    "ZAPISZ SOBIE KOD SWOJEJ FERMY. GDZIES POZA GRA.",
    "",
    "Kod to jedyny sposob, zeby wrocic do gospodarstwa. Gra trzyma go",
    "w pamieci przegladarki. Wyczyszczenie ciasteczek, tryb prywatny",
    "albo inne urzadzenie oznaczaja, ze przegladarka tego kodu juz nie",
    "zna - i bez zapisanego kodu nie ma jak odnalezc fermy.",
    "",
    "Stan fermy lezy na serwerze, nie w przegladarce. Z kodem wrocisz",
    "do niej z kazdego telefonu i kazdego komputera.",
])
para("""
Kod widzisz na ekranie powitalnym przy kazdym wejsciu do gry. Ten sam kod mozesz
podac koledze - wejdzie na TWOJA ferme i bedzie na niej gral razem z toba.
""")

title("3. EKRAN GRY")
raw("""
  +------------------------------------------------------------------------+
  |  [monety]  150      [jajko]  12      [worek]  20      [kura]  4/20     |
  +------------------------------------------------------------------------+
         kasa           jaja w         pasza          ptaki / miejsca
                        magazynie      w kg           w kurniku
  |                                                                        |
  |     KURNIK                    INKUBATOR                                |
  |     (dotknij, zeby otworzyc    (dotknij, zeby wlozyc jaja              |
  |      panel kurnika)             i odebrac pisklęta)                    |
  |                                                                        |
  |   ========================= WYBIEG ==================================  |
  |                                                                        |
  |     kury chodza, znosza jaja. Jaja lezace na trawie ZBIERASZ PALCEM.   |
  |     Tu tez wchodzi lis - w lisa sie KLIKA, zeby go przegonic.          |
  |                                                                        |
  |   =====================================================================|
  |                                                                        |
  |     MAGAZYN                   SKLEP                                    |
  |     (pasza i pojemnosc        (sprzedaz jaj, kupno paszy,              |
  |      na jaja)                  kupno kur i kogutow, szczepionki)       |
  +------------------------------------------------------------------------+
""".rstrip())
para("""
Pies, jesli go kupisz, stoi przy kurniku. Plot widac dookola wybiegu - zmienia
wyglad przy kazdej rozbudowie.
""")

title("4. PETLA GRY - OD CZEGO ZACZAC")
para("""
SUWAKI. Kupno i sprzedaz kur, ubicie chorej, pasza, szczepienie, plot, pies
i kazda rozbudowa to SUWAK: przeciagnij palcem w prawo. Wystarczy 2/3 drogi
- gdy galka pokaze ptaszek, a pole pojasnieje, pusc palec. Samo dotkniecie
nic nie robi - nie kupisz nic przypadkiem. W sklepie kazda rasa ma dwie
kolumny: po lewej KUP KURE i KUP KOGUTA, po prawej SPRZEDAJ KURE
i SPRZEDAJ KOGUTA. Sprzedaz jaj i wkladanie jaj do inkubatora to zwykle
przyciski, bo klika sie je co chwile.
""")
raw("""
  1. ZBIERAJ JAJA z wybiegu. Dotknij jajka palcem, idzie do magazynu.
     Jaj powyzej %d sztuk naraz gra nie kladzie na trawie - nadmiar
     ladzie prosto w magazynie.

  2. SPRZEDAWAJ JAJA w sklepie, po %d sztuk na dotkniecie. Ida najstarsze,
     bo te najszybciej gnija. To biezacy przychod na pasze.

  3. KUPUJ PASZE, zanim sie skonczy. Pusty magazyn = stado zaczyna padac
     po %g minutach.

  4. WKLADAJ JAJA DO INKUBATORA. %d jaja jednej rasy = jedno pisklę tej rasy.
     Pisklę rosnie i zmienia sie w dorosla kure.

  5. SPRZEDAWAJ WYHODOWANE KURY. Za dorosla sztuke dostajesz 70%% jej ceny
     zakupu - a wyhodowana z wlasnych jaj nie kosztowala cie nic poza pasza.

  6. ROZBUDOWUJ. Wiekszy kurnik to wiecej kur, wiekszy inkubator to wiecej
     piskląt naraz, wiekszy magazyn to wiecej jaj i tanszy worek paszy.
""" % (BAL["run"]["max_eggs_on_ground"], ECO["egg_sale_lot"],
       round(BAL["hunger"]["grace_minutes"] / SCALE, 1),
       BAL["incubator"]["eggs_per_chick"]))
raw("")
para("""
WAZNE: kura znosi jaja tylko wtedy, gdy na fermie stoi KOGUT JEJ RASY. Kupienie
samych kur nic nie da. Kogut kosztuje %d%% ceny kury tej samej rasy (kura za
%s to kogut za %s), ale wystarczy jeden na cala rase. Przy sprzedazy dziala
ten sam mnoznik: kogut idzie za %d%% ceny skupu kury (kura %s, kogut %s).
""" % (round(ECO.get("rooster_price_multiplier", 2.5) * 100),
       zl(BREEDS[0]["price"]),
       zl(float(BREEDS[0]["price"]) * ECO.get("rooster_price_multiplier", 2.5)),
       round(ECO.get("rooster_price_multiplier", 2.5) * 100),
       zl(BREEDS[0]["sell_price"]),
       zl(float(BREEDS[0]["sell_price"]) * ECO.get("rooster_price_multiplier", 2.5))))

title("5. JAJA: ZNOSZENIE, MAGAZYN, GNICIE")
para("""
Kazda rasa znosi w swoim tempie (tabela ras nizej). Jaja z wybiegu zbierasz
palcem; gdy nie ma cie w grze, jaja omijaja wybieg i ida prosto do magazynu.
""")
para("""
MAGAZYN MA LIMIT. Przy pelnym magazynie kury przestaja odkladac jaja - nowe
po prostu przepadaja. Limit podnosisz rozbudowa magazynu.
""")
para("""
JAJA GNIJA. Niesprzedane jajko psuje sie po %g godzinach REALNEGO czasu
i znika z magazynu. Nie da sie zrobic zapasu na tydzien.
""" % ECO["egg_spoil_hours"])

title("6. PASZA I GLOD")
para("""
Kazdy dorosly ptak zjada %g kg paszy na godzine, pisklę %g tego. Na starcie
pasze kupujesz w workach: %s za %d kg (cena jak w sklepie rolniczym). Im
wiekszy magazyn, tym wieksza jednostka (big-bag, dostawa luzem, paszowoz)
i nizsza cena za kilogram - tabela w rozdziale MAGAZYN. Pasze kupuje sie
JEDNYM SUWAKIEM, jedna jednostka na raz.
""" % (round(ECO["feed_per_hen_minute"] * 60 * SCALE, 2), ECO.get("chick_feed_multiplier", 0.5),
       zl(ECO["feed_pack_price"]), ECO["feed_pack_size"]))
para("""
ZANIM WYJDZIESZ Z GRY: kup paszy na cala przerwe. Kury jedza tez wtedy, gdy nie
grasz, a magazyn trzyma tylko tyle jaj, ile sie w nim miesci - reszta przepada.
""")
para("""
Gdy pasza sie skonczy: przez %g minut nic sie nie dzieje, potem kury zaczynaja
padac - jedna co %g sekund przy stadzie %d sztuk, czesciej przy wiekszym.
Bez paszy STOI TEZ INKUBATOR I ODCHOW piskląt.
""" % (round(BAL["hunger"]["grace_minutes"] / SCALE, 1),
       round(BAL["hunger"]["death_interval_seconds"] / SCALE),
       BAL["hunger"]["reference_hens"]))

title("7. ROZMNAZANIE - TU SA PIENIADZE")
para("""
%d jaja jednej rasy wlozone do inkubatora daja jedno pisklę tej rasy. Inkubator
ma miejsca - kazde miejsce grzeje jedna partie naraz. Na starcie masz %d miejsca.
""" % (BAL["incubator"]["eggs_per_chick"], BAL["incubator"]["slots"]))
para("""
Pelny cykl to WYLEG (inkubator) plus ODCHOW (pisklę rosnie na wybiegu). Czasy
dla kazdej rasy sa w tabeli nizej, w czasie przy zegarku.
""")
para("""
Z jaj wykluwa sie mniej wiecej tyle samo KOGUTKOW co KUREK (jak w naturze -
%d%% to kogutki). Kogutek nie niesie, ale idzie do skupu za %d%% ceny kury tej
rasy - jeden kogut na rase wystarczy, reszte sprzedawaj.
""" % (round(BAL["incubator"].get("rooster_share", 0.5) * 100),
       round(ECO.get("rooster_price_multiplier", 2.5) * 100)))
para("""
Dorosla sztuka sprzedaje sie za 70% ceny zakupu rasy. Kupiona kura to strata;
WYHODOWANA to czysty zysk, bo jaja byly twoje. Na tym stoi cala gra - i dlatego
hamulcem jest czas odchowu, a nie pieniadze.
""")

title("8. TABELA RAS")
rows = []
for b in BREEDS:
    name = S.get(b["name"], b["id"])
    cycle = real_seconds(float(b["incubate_seconds"]) + float(b["grow_seconds"]))
    rows.append([
        name,
        zl(b["price"]),
        zl(b["sell_price"]),
        gr(b["egg_value"]),
        czas_krotki(real_seconds(b["egg_seconds"])),
        czas_krotki(cycle),
        b.get("coop_level", 0),
    ])
table(["rasa", "kupno", "sprzed.", "jajko", "znosi", "odchow", "lvl"],
      rows, align="lrrrrrr")
para("""
"lvl" to poziom kurnika, od ktorego rasa jest w ogole dostepna w sklepie.
"znosi" to odstep miedzy jajami jednej kury, "odchow" to pelny czas od
wlozenia jaj do inkubatora do doroslej sztuki. Oba przy zegarku.
""")

def budowa(u) -> str:
    m = float(u.get("build_minutes", 0))
    return "od razu" if m <= 0 else ("%d min" % m if m < 60 else "%g h" % (m / 60))


def poziomy(cfg, wartosc, naglowek):
    """Lista poziomow, po dwie linijki na poziom - tabela z dlugimi nazwami
    nie miescila sie w 78 znakach (czytane na telefonie). Poziom startowy to 1.
    `naglowek` zostal dla zgodnosci wywolan."""
    def linie(nr, nazwa, opis):
        raw("  %2d. %s\n      %s" % (nr, nazwa, opis))
    linie(1, S.get(cfg.get("name", ""), cfg.get("name", "")), "%s - na start" % wartosc(cfg, None))
    for i, u in enumerate(cfg["upgrades"], start=2):
        linie(i, S.get(u["name"], u["name"]),
              "%s - %s, budowa %s" % (wartosc(cfg, u), zl(u["price"]), budowa(u)))


title("9. KURNIK")
coop = BAL["buildings"]["coop"]
poziomy(coop, lambda c, u: "%s miejsc" % num((u or c)["capacity"]), "miejsc")
para("""
Limit liczy WSZYSTKIE dorosle ptaki razem z kogutami. Ponad limit nie kupisz
ptaka, a podrosniete pisklę czeka przy inkubatorze, az zwolni sie miejsce.
Kurnik zmienia wyglad na poziomie 4 i 7.
""")
para("""
ROZBUDOWA TRWA. Kurnik, magazyn i inkubator buduja sie od %d minut do %d minut
(czas przy zegarku, leci tez, gdy nie grasz). Placisz od razu, a do konca
budowy budynek dziala na starym poziomie. Nad budynkiem wisi tabliczka
z czasem. Plot i pies sa od razu.
""" % (min(u.get("build_minutes", 0) for u in coop["upgrades"]),
       max(u.get("build_minutes", 0) for u in coop["upgrades"])))

title("10. MAGAZYN")
st = BAL["buildings"]["storage"]
poziomy(st, lambda c, u: "limit %s jaj" % num((u or c)["egg_capacity"]), "limit jaj")
rows = [["1", "%s %s" % (st.get("feed_unit", "worek"), dane.weight(ECO["feed_pack_size"])),
         zl(ECO["feed_pack_price"]), "%.2f zl" % (ECO["feed_pack_price"] / ECO["feed_pack_size"])]]
for i, u in enumerate(st["upgrades"], start=2):
    rows.append([str(i), "%s %s" % (u["feed_unit"], dane.weight(u["pack_size"])), zl(u["pack_price"]),
                 "%.2f zl" % (u["pack_price"] / u["pack_size"])])
table(["poz.", "pasza (jeden suwak)", "cena", "za kg"], rows, align="rlrr")
para("""
Rozbudowa magazynu robi dwie rzeczy naraz: podnosi limit jaj i pozwala kupowac
pasze w wiekszych jednostkach, a im wieksza jednostka, tym tanszy kilogram
(od %.2f zl na starcie do %.2f zl na ostatnim poziomie). Magazyn zmienia
wyglad na poziomie 4 i 7.
""" % (ECO["feed_pack_price"] / ECO["feed_pack_size"],
       st["upgrades"][-1]["pack_price"] / st["upgrades"][-1]["pack_size"]))

title("11. INKUBATOR")
inc = BAL["incubator"]
poziomy(inc, lambda c, u: "%s jaj naraz (%s pisklat)" % (num((u or c)["eggs"]), num((u or c)["slots"])),
        "jaj / pisklat")
para("""
Z %d jaj wykluwa sie jedno pisklę, wiec inkubator na 48 jaj grzeje naraz
16 pisklat. Inkubatory sa tanie jak w sklepie rolniczym - drogie sa kurniki.
""" % BAL["incubator"]["eggs_per_chick"])

title("12. LIS")
fox = BAL["fox"]
para("""
Lis to glowny powod, dla ktorego warto wydac pieniadze na obrone.
""")
raw("""
  KIEDY PRZYCHODZI
    zawsze             kostka co %g min realnych, szansa %.0f%%
                       - tak samo, gdy grasz i gdy nie grasz
    gdy nie grasz      cala wizyta dzieje sie od razu: lis zabija
                       i znika, nie czeka na Ciebie. Co zrobil,
                       przeczytasz w KRONICE FERMY
    nie przyjdzie      przez pierwsze %g min nowej fermy
                       ani gdy masz mniej niz %d kur

  JAK PRZYCHODZI
    najpierw CZAI SIE w krzakach na polnoc albo na poludnie od wybiegu
    (%g-%g s - zza krzaka widac uszy), potem idzie pod plot (%g s).
    Pod plotem plot losuje, czy lisa zatrzyma. Jesli tak - lis drapie,
    zawraca i znika w krzakach. Jesli nie - przeskakuje plot.

  CO ROBI NA WYBIEGU
    zabija jedna kure co %g-%g sekund REALNYCH
    (czas losowany od nowa po kazdej kurze)
    odchodzi po %d-%d zabitych kurach
    bezpiecznik: nie zostaje dluzej niz %g minut

  JAK GO PRZEGONIC RECZNIE
    KLIKAJ W NIEGO. Trzeba %d trafien. Licznik widac nad lisem.
    Przegoniony reka wraca %g razy szybciej niz normalnie -
    chyba ze masz psa albo plot.

  RZEZ
    Gdy ferma NIE MA PSA, okolo %.0f%% lisow, ktore wejda na wybieg,
    wpada w szal: zabija %g razy szybciej i nie odchodzi, dopoki nie
    wybije CALEGO stada. Ratunek: klikac (te same %d trafien) albo
    miec psa - przy psie rzezi nie ma wcale.
""".rstrip() % (
    fox["roll_minutes"], fox["chance"] * 100,
    fox["grace_minutes"], fox["min_hens"],
    fox.get("lurk_min_seconds", 10), fox.get("lurk_max_seconds", 30), fox.get("approach_seconds", 4),
    fox["kill_interval_min"], fox["kill_interval_max"],
    fox["kills_min"], fox["kills_max"],
    fox["visit_max_minutes"],
    fox["scare_taps"], 1.0 / fox["hand_return_factor"],
    fox["massacre_chance"] * 100, round(1.0 / fox["massacre_pace_factor"], 1), fox["scare_taps"]))

title("13. PSY I PLOT")
dogs = BAL["buildings"]["dog"]["upgrades"]
raw("  PSY:")
for nr, d in enumerate(dogs, start=1):
    raw("  %2d. %s\n      %s - rzuca sie na lisa co %g s, przegania w %.0f%%, zagryza w %.0f%%"
        % (nr, d["name"], zl(d["price"]), d["interval"], d["chance"] * 100, d["kill_chance"] * 100))
para("""
Pies pracuje sam, bez twojego udzialu, takze gdy nie patrzysz. Gdy lis wejdzie,
pies rzuca kostka co tyle sekund. Przy udanej probie owczarek moze lisa ZAGRYZC -
wtedy lis zostaje rozszarpany na wybiegu, a nastepny przychodzi %g razy
pozniej niz zwykle.
""" % fox["killed_return_multiplier"])
guard = BAL["buildings"]["guard"]["upgrades"]
raw("")
raw("  PLOTY:")
for nr, u in enumerate(guard, start=1):
    raw("  %2d. %s\n      %s - lis zawraca w %.0f%% podejsc" % (nr, u["name"], zl(u["price"]),
                                                            u["block_chance"] * 100))
para("""
Plot dziala INACZEJ niz pies: nie wygania lisa z wybiegu, tylko z takim
prawdopodobienstwem w ogole go nie wpuszcza. Plot i pies licza sie osobno,
wiec najlepiej miec oba. Plot zmienia wyglad na kazdym poziomie.
""")

title("14. CHOROBA")
dis = BAL["disease"]
def ryzyko(n):
    pts = dis["rate_per_hour"]
    if n <= pts[0][0]:
        return pts[0][1]
    for a, b in zip(pts, pts[1:]):
        if n <= b[0]:
            return a[1] + (b[1] - a[1]) * (n - a[0]) / float(b[0] - a[0])
    return pts[-1][1]
def co_ile(n):
    r = ryzyko(n)
    if r <= 0:
        return "nigdy"
    h = 1.0 / r
    return "srednio co %g h" % round(h, 1) if h >= 1 else "srednio co %d min" % round(h * 60)
raw("""
  KIEDY WYBUCHA  co minute kostka; szansa rosnie z wielkoscia stada:
                   do %d ptakow     %s
                   %d ptakow        %s
                   %d ptakow        %s
                   %d i wiecej     %s
                 (licza sie dorosle ptaki, kury i koguty). Tak samo, gdy
                 grasz i gdy nie grasz. Przez pierwsze %g min nowej fermy
                 nikt nie choruje.

  JAKA RASA      choroba atakuje JEDNA rase naraz (drozsza chetniej).
                 Inne rasy sa odporne - im wiecej ras, tym mniej tracisz.

  JAK SIE SZERZY pierwszy ptak choruje od razu, potem zaraza przechodzi
                 na kolejnego zdrowego, NIEZASZCZEPIONEGO ptaka tej rasy
                 co %g s - az przejdzie przez cala rase. Potem wygasa.

  CHORY PTAK     nie znosi. Po %g minutach pada albo zdrowieje: przezywa
                 od %.0f%% do %.0f%% chorych (losowane przy wybuchu, co
                 %.0f%%). Ozdrowialy jest odporny do konca zycia. LEKU NIE
                 MA - chorego mozesz sprzedac do McDonalda za %s.

  SZCZEPIENIE    %s za kazda ZDROWA kure, chroni DO KONCA ZYCIA. Chorej nie
                 wyleczy. Dziala na kury zyjace w chwili szczepienia - nowe
                 pisklęta trzeba zaszczepic osobno. Zaszczepienie stada,
                 gdy ognisko juz ruszylo, ratuje te, ktorych jeszcze nie
                 zlapalo.

  PO OGNISKU     %g-%g godzin spokoju - wtedy nic nie wybucha.

  STAN W KURNIKU panel kurnika pokazuje wiersz CHOROBA: ognisko w toku,
                 spokoj (ile jeszcze) albo ryzyko przy obecnym stadzie.
""".rstrip() % (
    dis["rate_per_hour"][0][0], co_ile(dis["rate_per_hour"][0][0]),
    dis["rate_per_hour"][1][0], co_ile(dis["rate_per_hour"][1][0]),
    dis["rate_per_hour"][2][0], co_ile(dis["rate_per_hour"][2][0]),
    dis["rate_per_hour"][-1][0], co_ile(dis["rate_per_hour"][-1][0]),
    dis["grace_minutes"], dis["spread_seconds"], dis["death_minutes"],
    dis["survive_share_min"] * 100, dis["survive_share_max"] * 100, dis["survive_share_step"] * 100,
    zl(dis["mcdonalds_price"]), zl(dis["vaccine_price_per_hen"]),
    dis["calm_hours_min"], dis["calm_hours_max"]))

title("15. CZAS W GRZE")
para("""
Czas gry plynie %g razy wolniej od zegarka: jedna minuta przy zegarku to okolo
%d sekund w grze. Wszystkie czasy w tej instrukcji i W GRZE (panele, budowy,
"pasza starczy na", wiek gospodarstwa) sa podane przy zegarku - w czasie
ziemskim. Gra nie pokazuje juz "dni gospodarstwa".
""" % (round(1.0 / SCALE, 2), round(60 * SCALE)))
para("""
Gra liczy czas TAK SAMO, gdy grasz i gdy nie grasz. Zostawiona na noc ferma
znosi jaja, zjada pasze, choruje i goszczy lisa. Po powrocie gra nadrabia
zaleglosci - maksymalnie %d godziny za jednym razem.
""" % BAL["offline"]["max_hours"])
para("""
Stan zapisuje sie sam co kilka sekund i trafia na serwer. Zapis idzie takze
w chwili, gdy przelaczasz sie na inna karte albo zamykasz gre.
""")

title("16. CEL")
para("""
Uzbieraj %s. Droga najkrotsza: zbuduj stado jednej z drozszych ras, trzymaj
inkubator caly czas pelny i sprzedawaj odchowane sztuki. Jaja sprzedawaj na
biezaco, zeby bylo na pasze.
""" % zl(BAL["win"]["money"]))
para("""
GAME OVER. Gdy na fermie nie zostanie zadna para kura + kogut tej samej rasy,
inkubator i odchow stoja puste, w magazynie nie ma jaj na wyleg, a za cala
gotowke (z jajami i ptakami na sprzedaz) nie da sie dokupic brakujacej pary
- gra konczy sie plansza GAME OVER: "Niestety, jesteś marnym hodowcą.
Poniosłeś bankructwo." Przycisk zaczyna nowa ferme pod TYM SAMYM kodem.
""")
para("""
NOWA RASA I OSIAGNIECIA. Pierwsza sztuka kazdej rasy otwiera wielkie okno
z gratulacjami, malowanym portretem rasy, jej historia i trzema
ciekawostkami. Wszystkie zdobyte karty ras sa potem pod GWIAZDKA w lewym
gornym rogu (OSIAGNIECIA). Niezdobyte rasy widac tam jako ciemne sylwetki.
""")
para("""
KRONIKA FERMY. Po przerwie dluzszej niz %g godziny gra pokazuje kronike:
ile jaj zniosly kury, ile przepadlo, ile razy byl lis i co zabral, czy
wybuchla choroba, co sie zbudowalo - i dziennik z godzinami ("02:14 Lis
wszedl na wybieg. Zabral ptakow: 6.").
""" % BAL["offline"].get("report_hours", 3))

title("17. SCIAGAWKA")
raw("""
  Kury nie znosza jaj          -> brakuje KOGUTA tej rasy
  Rasa wyszarzona w sklepie    -> za niski poziom kurnika (patrz tabela ras)
  Jaja znikaja z magazynu      -> gnija po %g h, albo magazyn jest pelny
  Kury padaja bez ostrzezenia  -> skonczyla sie pasza
  Kury zielenieja i padaja     -> CHOROBA: szczep zdrowe, chore do McDonalda
  Pisklę nie wyrasta           -> brak paszy albo pelny kurnik
  Lis na wybiegu               -> KLIKAJ W NIEGO (%d razy), kup psa i plot
  Nie moge wrocic do fermy     -> potrzebny KOD, zapisz go sobie poza gra
  Gra wyglada na cofnieta      -> odswiez z Ctrl+Shift+R
""".rstrip() % (ECO["egg_spoil_hours"], fox["scare_taps"]))

raw("")
rule("=")
raw("  Milej hodowli. Lis i tak przyjdzie.")
rule("=")

(ROOT / "INSTRUKCJA.txt").write_text("\n".join(L) + "\n", encoding="utf-8")
print("zapisano INSTRUKCJA.txt (%d wierszy)" % len(L))
