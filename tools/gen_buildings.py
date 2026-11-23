#!/usr/bin/env python3
"""Robi warianty wygladu budynkow na kolejne poziomy rozbudowy.

Tomek poprosil, zeby rozbudowa bylo widac na farmie, a nie tylko w liczbach
w panelu. Zamiast rysowac dziewiec osobnych kurnikow, kazdy budynek ma trzy
poziomy wygladu:

    tier 1  - plik podstawowy (coop.svg)        -> poziomy 0-2
    tier 2  - coop_2.svg, "duzy"                -> poziomy 3-5
    tier 3  - coop_3.svg, "przemyslowy"         -> poziomy 6+

Warianty powstaja TUTAJ, z pliku podstawowego: przemalowany dach plus kilka
dolozonych elementow. Dzieki temu poprawka w pliku bazowym (np. inny ksztalt
sciany) przechodzi na wszystkie poziomy po ponownym uruchomieniu skryptu:

    python3 tools/gen_buildings.py && godot --headless --path . --import

Zadnych filtrow SVG - ThorVG (rasteryzator Godota) ich nie obsluguje.
Tylko gradienty i sciezki, tak jak w reszcie grafik.
"""

import re
import pathlib

SRC = pathlib.Path(__file__).resolve().parent.parent / "assets" / "sprites" / "buildings"


def repaint(svg: str, gradient_id: str, colors: list[str]) -> str:
    """Podmienia stop-color w jednym gradiencie, zostawiajac offsety."""
    start = svg.index('id="%s"' % gradient_id)
    end = svg.index("Gradient>", start)
    block = svg[start:end]
    stops = re.findall(r'stop-color="#[0-9A-Fa-f]{6}"', block)
    assert len(stops) == len(colors), (gradient_id, len(stops), len(colors))
    for old, new in zip(stops, colors):
        block = block.replace(old, 'stop-color="%s"' % new, 1)
    return svg[:start] + block + svg[end:]


def add(svg: str, markup: str) -> str:
    """Dokłada elementy na koniec glownej grupy, czyli na wierzchu."""
    cut = svg.rindex("</g>")
    return svg[:cut] + markup + "\n  " + svg[cut:]


def note(svg: str, text: str) -> str:
    head = svg.index(">") + 1
    return svg[:head] + "\n  <!-- WYGENEROWANE przez tools/gen_buildings.py - nie edytuj recznie.\n       " + text + " -->" + svg[head:]


def save(name: str, svg: str) -> None:
    (SRC / (name + ".svg")).write_text(svg, encoding="utf-8")
    print("zapisano", name + ".svg")


# --------------------------------------------------------------------------
# KURNIK
# --------------------------------------------------------------------------
base = (SRC / "coop.svg").read_text(encoding="utf-8")

# Poziom 2: wiekszy kurnik - zielona dachowka, lukarna i druga latarnia.
s = repaint(base, "cRoof", ["#A8D98F", "#7FBE72", "#5E9A58"])
s = repaint(s, "cRoofSide", ["#6FAE66", "#4C8549"])
s = add(s, """
    <!-- lukarna: znak, ze kurnik ma juz pietro dla kur -->
    <path d="M120 186V132Q146 108 172 132v54Z" fill="#EBC591"/>
    <path d="M112 134 146 104 180 134q-10 8-20 2-14 10-28 0-10 6-20-2Z" fill="#7FBE72"/>
    <rect x="130" y="144" width="32" height="34" rx="6" fill="#C5E7F1"/>
    <path d="M146 144v34M130 161h32" stroke-width="3"/>

    <!-- druga latarnia, po lewej stronie -->
    <path d="M70 232v14" stroke-width="3.4"/>
    <path d="M60 246h20l5 22H55Z" fill="#FCE9B2"/>
    <path d="M58 268h24" stroke-width="3.4"/>""")
save("coop_2", note(s, "Kurnik, poziom wygladu 2 - rozbudowany."))

# Poziom 3: ferma przemyslowa - blacha, wywietrznik, wentylator, pas ostrzegawczy.
s = repaint(base, "cRoof", ["#D7DEE4", "#B3BDC6", "#8F9BA6"])
s = repaint(s, "cRoofSide", ["#9AA6B1", "#78848F"])
s = add(s, """
    <!-- blacha trapezowa na polaci -->
    <path d="M198 66 76 180M238 72 122 188M278 92 170 196M316 116 220 200M350 144 272 202"
          stroke="#FFFFFF" stroke-width="3" stroke-opacity="0.5" fill="none"/>

    <!-- wywietrznik dachowy zamiast choragiewki; musi sie zmiescic
         w plotnie 480x440, inaczej Godot utnie mu czubek -->
    <path d="M210 50v-12h32v12Z" fill="#8F9BA6"/>
    <circle cx="226" cy="22" r="17" fill="#C6CFD7"/>
    <path d="M226 5v34M209 22h34M214 10 238 34M238 10 214 34" stroke-width="3"/>

    <!-- wentylator na scianie bocznej -->
    <rect x="384" y="228" width="40" height="40" rx="6" fill="#B3BDC6"/>
    <circle cx="404" cy="248" r="13" fill="#6F7B86"/>
    <path d="M404 235v26M391 248h26" stroke="#D7DEE4" stroke-width="3"/>

    <!-- pas ostrzegawczy na podmurowce -->
    <path d="M90 382h12l-10 14H90ZM114 382h12l-10 14h-12ZM138 382h12l-10 14h-12ZM162 382h12l-10 14h-12Z"
          fill="#F2C14E" stroke="none"/>""")
save("coop_3", note(s, "Kurnik, poziom wygladu 3 - ferma przemyslowa."))

# --------------------------------------------------------------------------
# MAGAZYN
# --------------------------------------------------------------------------
base = (SRC / "storage.svg").read_text(encoding="utf-8")

# Poziom 2: wiekszy magazyn - ceglasty dach, przenosnik i drabina na silos.
s = repaint(base, "sRoof", ["#F6B894", "#E08A68", "#C4714F"])
s = repaint(s, "sRoofSide", ["#D1795C", "#B35F46"])
s = add(s, """
    <!-- przenosnik z silosu na stryszek -->
    <path d="M336 150 206 186" stroke="#9AA6B1" stroke-width="16"/>
    <path d="M336 150 206 186" stroke="#CDD5DC" stroke-width="7"/>
    <path d="M206 186v22" stroke="#9AA6B1" stroke-width="10"/>

    <!-- drabina na silosie -->
    <path d="M414 150v212M432 150v212" stroke="#9AA6B1" stroke-width="4"/>
    <path d="M414 176h18M414 206h18M414 236h18M414 266h18M414 296h18M414 326h18"
          stroke="#9AA6B1" stroke-width="3.4"/>

    <!-- wywietrznik na kalenicy stodoly -->
    <path d="M158 76h44v-18h-44Z" fill="#E08A68"/>
    <path d="M152 58h56l-28-22Z" fill="#D1795C"/>""")
save("storage_2", note(s, "Magazyn, poziom wygladu 2 - rozbudowany."))

# Poziom 3: magazyn przemyslowy - blacha, drugi silos, pasy ostrzegawcze.
s = repaint(base, "sRoof", ["#D7DEE4", "#AEB9C2", "#8E9AA5"])
s = repaint(s, "sRoofSide", ["#97A3AE", "#7A8691"])
s = add(s, """
    <!-- drugi, chudszy silos tuz obok -->
    <path d="M296 176h44v192a10 10 0 0 1-10 10h-24a10 10 0 0 1-10-10Z" fill="#CDD5DC"
          stroke="#885635" stroke-width="4.2"/>
    <path d="M296 176q22-44 44 0Z" fill="#AEB9C2" stroke="#885635" stroke-width="4.2"/>
    <path d="M296 226h44M296 276h44M296 326h44" stroke="#885635" stroke-width="2.5" stroke-opacity="0.45"/>

    <!-- przenosnik i drabina -->
    <path d="M336 150 206 186" stroke="#9AA6B1" stroke-width="16"/>
    <path d="M336 150 206 186" stroke="#CDD5DC" stroke-width="7"/>
    <path d="M414 150v212M432 150v212" stroke="#9AA6B1" stroke-width="4"/>
    <path d="M414 182h18M414 218h18M414 254h18M414 290h18M414 326h18"
          stroke="#9AA6B1" stroke-width="3.4"/>

    <!-- pas ostrzegawczy przy wrotach -->
    <path d="M118 374h14l-12 18h-14ZM146 374h14l-12 18h-14ZM174 374h14l-12 18h-14ZM202 374h14l-12 18h-14ZM230 374h12l-12 18h-12Z"
          fill="#F2C14E" stroke="none"/>""")
save("storage_3", note(s, "Magazyn, poziom wygladu 3 - przemyslowy."))

# --------------------------------------------------------------------------
# INKUBATOR
# --------------------------------------------------------------------------
base = (SRC / "incubator.svg").read_text(encoding="utf-8")

# Poziom 2: wiekszy inkubator - szuflady na jaja i wiecej kontrolek.
s = repaint(base, "iRoof", ["#F7D08A", "#E0A94F", "#C98F3B"])
s = repaint(s, "iRoofSide", ["#D79F49", "#B9833A"])
s = add(s, """
    <!-- druga komora postawiona na dachu: widac, ze maszyna urosla -->
    <path d="M216 136h108a14 14 0 0 1 14 14v38H216Z" fill="url(#iBody)"/>
    <path d="M208 92h124l12 18H208Z" fill="url(#iRoof)"/>
    <path d="M208 110h136v16H208Z" fill="#40BCA6"/>
    <circle cx="258" cy="160" r="20" fill="url(#iGlow)" stroke-width="3.4"/>
    <ellipse cx="258" cy="162" rx="9" ry="12" fill="#FEF9ED" stroke-width="2.5"/>
    <circle cx="308" cy="150" r="7" fill="#A1E384" stroke-width="3"/>
    <circle cx="308" cy="172" r="7" fill="#F9D570" stroke-width="3"/>

    <!-- szuflada na tace z jajami w podstawie -->
    <rect x="172" y="342" width="96" height="28" rx="7" fill="#FCE9B2"/>
    <path d="M206 356h28" stroke-width="4"/>""")
save("incubator_2", note(s, "Inkubator, poziom wygladu 2 - rozbudowany."))

# Poziom 3: inkubator przemyslowy - stal, rury, panel sterowania.
s = repaint(base, "iRoof", ["#D7DEE4", "#AEB9C2", "#8E9AA5"])
s = repaint(s, "iRoofSide", ["#97A3AE", "#7A8691"])
s = repaint(s, "iBase", ["#9AA6B1", "#78848F"])
s = add(s, """
    <!-- rury chlodzenia po bokach -->
    <path d="M60 210v150M44 226v118" stroke="#9AA6B1" stroke-width="11"/>
    <path d="M44 226q-8-24 16-24h18" stroke="#9AA6B1" stroke-width="11" fill="none"/>
    <path d="M60 252h-16M60 300h-16M60 344h-16" stroke="#CDD5DC" stroke-width="5"/>

    <!-- panel sterowania z wyswietlaczem -->
    <rect x="248" y="196" width="76" height="46" rx="8" fill="#3A4852"/>
    <rect x="256" y="204" width="60" height="22" rx="4" fill="#7FE3C2" stroke="none"/>
    <path d="M262 215h12M280 209v12M292 215h18" stroke="#1F3029" stroke-width="3" fill="none"/>
    <circle cx="264" cy="234" r="4" fill="#A1E384" stroke="none"/>
    <circle cx="280" cy="234" r="4" fill="#F9D570" stroke="none"/>
    <circle cx="296" cy="234" r="4" fill="#E67362" stroke="none"/>

    <!-- pas ostrzegawczy na podstawie -->
    <path d="M86 352h12l-10 16H86ZM110 352h12l-10 16h-12ZM134 352h12l-10 16h-12ZM158 352h12l-10 16h-12Z"
          fill="#F2C14E" stroke="none"/>""")
save("incubator_3", note(s, "Inkubator, poziom wygladu 3 - przemyslowy."))
