#!/usr/bin/env python3
"""Rysuje plot w czterech wersjach - po jednej na kazdy poziom rozbudowy.

Tomek: "Kolejne upgrade plotu i budynkow powinny ulepszac ich wyglad tez."
Poziom 0 (plot z pierwszego dnia) to plik fence_front.svg, rysowany recznie.
Poziomy 1-4 powstaja tutaj:

    1  mocny plot      - wyzsze slupki, trzecia poprzeczka
    2  sztachety       - gesty plot z zaostrzonymi sztachetami
    3  slupki z siatka - drewno plus stalowa siatka
    4  mur z siatka    - betonowe slupki, siatka i drut kolczasty

Kazdy poziom jest WYZSZY od poprzedniego. Plotno rosnie w gore, a dol
zostaje na miejscu - scena ustawia offset tekstury tak, zeby plot zawsze
stal na tej samej linii trawy (patrz _sync_fence w scenes/farm/farm.gd).

Uruchomienie:
    python3 tools/gen_fence.py && godot --headless --path . --import
"""

import pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "sprites" / "world"

## Przerwa na brame: miedzy tymi x nie ma przesla.
GATE_FROM, GATE_TO = 480, 600
WIDTH = 1080

DEFS = """<defs>
<linearGradient id="post" x1="0" y1="0" x2="0" y2="{h}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="{p0}"/>
  <stop offset="1" stop-color="{p1}"/>
</linearGradient>
</defs>"""


def posts(top, bottom, step, width, first=42, pointed=False):
    """Slupki co `step` pikseli, z przerwa na brame."""
    out = []
    x = first
    while x < WIDTH - 40:
        if GATE_FROM < x < GATE_TO - 20:
            x += step
            continue
        if pointed:
            # Sztacheta zaostrzona U GORY: od lewego ramienia w szpic i w dol.
            half = width / 2.0
            out.append(
                '<path d="M%g %gL%g %gL%g %gV%gH%gZ" fill="url(#post)" stroke="{line}" stroke-width="{sw}"/>'
                % (x, top + 12, x + half, top, x + width, top + 12, bottom, x))
        else:
            out.append(
                '<rect x="%g" y="%g" width="%g" height="%g" rx="5" fill="url(#post)" stroke="{line}" stroke-width="{sw}"/>'
                % (x, top, width, bottom - top))
        x += step
    return out


def rails(ys, thick, top_of_gate):
    """Poziome poprzeczki, przerwane na bramie."""
    out = []
    for y in ys:
        for a, b in ((50, GATE_FROM), (GATE_TO, WIDTH - 50)):
            out.append(
                '<rect x="%g" y="%g" width="%g" height="%g" rx="4" fill="{rail}" stroke="{line}" stroke-width="2.5"/>'
                % (a, y, b - a, thick))
    out.append(
        '<rect x="%g" y="%g" width="22" height="%g" rx="6" fill="url(#post)" stroke="{line}" stroke-width="{sw}"/>'
        % (GATE_FROM - 2, top_of_gate, 0))
    out.pop()
    return out


def mesh(top, bottom, color, step=26):
    """Stalowa siatka: dwa zestawy ukosnych linii, przerwane na bramie."""
    out = ['<g stroke="%s" stroke-width="2.2" stroke-opacity="0.75" fill="none">' % color]
    span = bottom - top
    for a, b in ((50, GATE_FROM), (GATE_TO, WIDTH - 50)):
        x = a - span
        while x < b:
            x1, y1, x2, y2 = x, bottom, x + span, top
            if x1 < a:
                y1 = bottom - (a - x1)
                x1 = a
            if x2 > b:
                y2 = top + (x2 - b)
                x2 = b
            if x1 < x2:
                out.append('<path d="M%g %g %g %g"/>' % (x1, y1, x2, y2))
            x += step
        x = a
        while x < b + span:
            x1, y1, x2, y2 = x, bottom, x - span, top
            if x1 > b:
                y1 = bottom - (x1 - b)
                x1 = b
            if x2 < a:
                y2 = top + (a - x2)
                x2 = a
            if x2 < x1:
                out.append('<path d="M%g %g %g %g"/>' % (x1, y1, x2, y2))
            x += step
    out.append("</g>")
    return out


def build(name, height, line, sw, p0, p1, rail, body, opis):
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
        % (WIDTH, height, WIDTH, height),
        "<!-- WYGENEROWANE przez tools/gen_fence.py - nie edytuj recznie.",
        "     " + opis + " -->",
        DEFS.format(h=height, p0=p0, p1=p1),
    ]
    parts += body
    parts.append("</svg>")
    svg = "\n".join(parts).format(line=line, sw=sw, rail=rail)
    (OUT / (name + ".svg")).write_text(svg, encoding="utf-8")
    print("zapisano %s.svg (%dx%d)" % (name, WIDTH, height))


# 1 - mocny plot: wyzsze slupki, trzy poprzeczki, ciemniejsze drewno
H = 86
build("fence_front_1", H, "#7E4F2A", 3.4, "#FBEBCB", "#DCC79F", "#F2E4C4",
      rails([24, 44, 64], 11, 0) + posts(10, H - 6, 60, 16),
      "Poziom 1: mocny plot - wyzszy, trzy poprzeczki.")

# 2 - sztachety: gesty plot z zaostrzonymi koncami
H = 98
body = rails([34, 62], 11, 0)
body += posts(16, H - 6, 30, 13, first=48, pointed=True)
body += posts(8, H - 6, 120, 20, first=42)
build("fence_front_2", H, "#7E4F2A", 3.4, "#FDF0D6", "#D9C098", "#E8D4AC", body,
      "Poziom 2: sztachety - gesty plot z zaostrzonymi koncami.")

# 3 - slupki z siatka
H = 112
body = mesh(22, H - 10, "#9AA6B1")
body += rails([16, H - 22], 10, 0)
body += posts(8, H - 6, 90, 18)
build("fence_front_3", H, "#6E5240", 3.4, "#F4E3C2", "#CFB58A", "#D9BE91", body,
      "Poziom 3: drewniane slupki z napieta stalowa siatka.")

# 4 - mur z siatka i drutem kolczastym
H = 128
body = mesh(30, H - 22, "#B6C0C8", step=22)
body.append('<rect x="50" y="%d" width="%d" height="20" rx="5" fill="#C8C2B4" stroke="{line}" stroke-width="{sw}"/>'
            % (H - 26, GATE_FROM - 50))
body.append('<rect x="%d" y="%d" width="%d" height="20" rx="5" fill="#C8C2B4" stroke="{line}" stroke-width="{sw}"/>'
            % (GATE_TO, H - 26, WIDTH - 50 - GATE_TO))
body += rails([24], 9, 0)
body += posts(4, H - 6, 110, 24)
# drut kolczasty na szczycie
body.append('<g stroke="#8C98A2" stroke-width="2.4" fill="none">')
for a, b in ((50, GATE_FROM), (GATE_TO, WIDTH - 50)):
    body.append('<path d="M%d 12 %d 12"/>' % (a, b))
    x = a + 14
    while x < b:
        body.append('<path d="M%g 4 %g 20M%g 4 %g 20"/>' % (x - 6, x + 6, x + 6, x - 6))
        x += 28
body.append("</g>")
build("fence_front_4", H, "#5E5A52", 3.8, "#E7E3D8", "#B9B4A6", "#CFC9BA", body,
      "Poziom 4: betonowe slupki, stalowa siatka i drut kolczasty.")
