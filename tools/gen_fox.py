#!/usr/bin/env python3
"""Lis z czesci do animacji szkieletowej.

Po co to jest
------------
Do 12.17 lis byl jednym obrazkiem (fox.svg) i druga klatka "w locie"
(fox_leap.svg). Sunal po wybiegu jak sanie i obracal sie o 180 stopni w jednej
klatce. Wlasciciel (24.11): "zeby poruszal lapami, przednie w tyl, tylne
w przod i odwrotnie, zeby tulow sie zginal - jak czworonog, a nie samolot".

Ten skrypt tnie tamtego lisa na czesci, ktore scena porusza osobno:

    tylna polowa tulowia, przednia polowa tulowia (zginaja sie w stawie),
    glowa (kiwa sie), ogon (faluje), lapa (jedna grafika, uzyta 4 razy),
    cien (zostaje na ziemi, gdy lis skacze).

Wszystkie wspolrzedne sa w ukladzie STAREGO fox.svg (196 x 116, lis patrzy
w prawo), wiec sylwetka zostaje ta sama, tylko rusza sie po kawalku.

Wynik:
    assets/sprites/animals/fox_parts/*.svg
    scenes/farm/fox_rig_data.gd   (punkty obrotu i ramki czesci dla sceny)

    python3 -I tools/gen_fox.py
"""

import math
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sprites" / "animals" / "fox_parts"
DATA = ROOT / "scenes" / "farm" / "fox_rig_data.gd"

STROKE = "#8A6A55"
SW = 4

# Tulow: ta sama elipsa co w starym fox.svg.
CX, CY, RX, RY = 96.0, 64.0, 52.0, 24.0
# Staw "kregoslupa": wokol niego obracaja sie obie polowy tulowia.
JOINT = (96.0, 70.0)
# Przy ktorym x polowy na siebie zachodza (przednia przykrywa tylna).
REAR_TO = 106.0
FRONT_FROM = 86.0
# Lapy: biodra i barki. Dlugosc lapy liczona od stawu do podloza.
LEG_LEN = 27.0
HIPS = {
    "hind_far": (66.0, 80.0),
    "hind_near": (79.0, 82.0),
    "front_far": (131.0, 80.0),
    "front_near": (119.0, 82.0),
}
NECK = (140.0, 60.0)
TAIL_BASE = (52.0, 60.0)
SHADOW = (96.0, 107.0)
# Punkt starego sprajta, ktory w scenie lezal w (0, 0) wezla lisa.
ORIGIN = (98.0, 120.0)

BODY_GRADIENT = """
    <radialGradient id="fxBody" cx="86" cy="58" r="64" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFA863"/>
      <stop offset="0.6" stop-color="#F08A42"/>
      <stop offset="1" stop-color="#D46A28"/>
    </radialGradient>"""


def y_on_ellipse(x: float) -> float:
    """Polowa wysokosci elipsy tulowia przy danym x."""
    t = (x - CX) / RX
    return RY * math.sqrt(max(0.0, 1.0 - t * t))


def svg(box: tuple, body: str, defs: str = "", note: str = "") -> str:
    x, y, w, h = box
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{w:g}" height="{h:g}" viewBox="{x:g} {y:g} {w:g} {h:g}">
  <!-- {note}
       Plik generowany: tools/gen_fox.py. Nie poprawiaj recznie. -->
  <defs>{defs}
  </defs>
{body}
</svg>
"""


def rear() -> str:
    dy = y_on_ellipse(REAR_TO)
    top, bot = (REAR_TO, CY - dy), (REAR_TO, CY + dy)
    arc = f"M{top[0]:.2f} {top[1]:.2f}A{RX:g} {RY:g} 0 1 0 {bot[0]:.2f} {bot[1]:.2f}"
    body = f"""  <path d="{arc}Z" fill="url(#fxBody)"/>
  <path d="M50 74Q74 82 104 81Q80 81 50 74Z" fill="#FFF3DF"/>
  <path d="{arc}" fill="none" stroke="{STROKE}" stroke-width="{SW}" stroke-linecap="round"/>"""
    return svg((40, 36, 72, 56), body, BODY_GRADIENT,
               "Tylna polowa tulowia lisa. Prawy brzeg chowa sie pod przednia polowa.")


def front() -> str:
    dy = y_on_ellipse(FRONT_FROM)
    top, bot = (FRONT_FROM, CY - dy), (FRONT_FROM, CY + dy)
    arc = f"M{top[0]:.2f} {top[1]:.2f}A{RX:g} {RY:g} 0 1 1 {bot[0]:.2f} {bot[1]:.2f}"
    body = f"""  <path d="{arc}Z" fill="url(#fxBody)"/>
  <path d="M88 81Q118 82 142 72Q118 86 88 84Z" fill="#FFF3DF"/>
  <!-- bialy podgardle, jak u prawdziwego lisa -->
  <path d="M128 50Q150 58 146 78Q134 84 126 72Q124 60 128 50Z" fill="#FFF3DF"/>
  <path d="{arc}" fill="none" stroke="{STROKE}" stroke-width="{SW}" stroke-linecap="round"/>"""
    return svg((82, 36, 72, 56), body, BODY_GRADIENT,
               "Przednia polowa tulowia lisa z podgardlem.")


def head() -> str:
    defs = """
    <radialGradient id="fxHead" cx="152" cy="46" r="30" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFB273"/>
      <stop offset="1" stop-color="#E67D36"/>
    </radialGradient>"""
    body = f"""  <g stroke="{STROKE}" stroke-width="{SW}" stroke-linejoin="round" stroke-linecap="round">
    <ellipse cx="152" cy="48" rx="26" ry="24" fill="url(#fxHead)"/>
    <path d="M138 28L132 4l20 16Z" fill="#E67D36"/>
    <path d="M163 26L175 4l9 24Z" fill="#E67D36"/>
    <path d="M140 25l-2-12l10 7Z" fill="#4A3328" stroke="none"/>
    <path d="M166 24l6-11l4 11Z" fill="#4A3328" stroke="none"/>
    <path d="M156 42q24 2 28 13q-6 11-28 9q-8-11 0-22Z" fill="#FFF6E6"/>
    <ellipse cx="185" cy="54" rx="6" ry="5" fill="#3A2A20" stroke="none"/>
    <path d="M155 35q7-4 13 0" fill="none"/>
    <circle cx="161" cy="40" r="4" fill="#3A2A20" stroke="none"/>
    <circle cx="162.4" cy="38.6" r="1.5" fill="#FFFFFF" stroke="none"/>
  </g>"""
    return svg((122, 0, 74, 76), body, defs, "Glowa lisa. Obraca sie wokol szyi.")


def tail() -> str:
    defs = """
    <linearGradient id="fxTail" x1="4" y1="30" x2="58" y2="64" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFF3DF"/>
      <stop offset="0.32" stop-color="#FFF3DF"/>
      <stop offset="0.36" stop-color="#F59A4E"/>
      <stop offset="1" stop-color="#D46A28"/>
    </linearGradient>"""
    body = f"""  <path d="M58 56Q30 70 8 46Q2 30 18 26Q30 26 40 40Q48 50 58 56Z" fill="url(#fxTail)"
        stroke="{STROKE}" stroke-width="{SW}" stroke-linejoin="round"/>"""
    return svg((0, 20, 64, 50), body, defs,
               "Kita lisa, puszysta, z bialym koncem. Faluje wokol nasady.")


def leg() -> str:
    # Lapa pionowo w dol od stawu (0, 0). Gorna czesc ruda, dolna czarna -
    # rude lisy maja "ponczochy".
    body = f"""  <path d="M0 0V{LEG_LEN:g}" stroke="{STROKE}" stroke-width="13" stroke-linecap="round"/>
  <path d="M0 0V{LEG_LEN:g}" stroke="#D46A28" stroke-width="9" stroke-linecap="round"/>
  <path d="M0 {LEG_LEN * 0.5:g}V{LEG_LEN:g}" stroke="#4A3328" stroke-width="9" stroke-linecap="round"/>
  <ellipse cx="2" cy="{LEG_LEN + 1:g}" rx="6.5" ry="4" fill="#3A2A20" stroke="{STROKE}" stroke-width="2"/>"""
    return svg((-9, -8, 20, LEG_LEN + 16), body, "",
               "Lapa lisa (jedna grafika na cztery lapy). Staw w punkcie (0, 0).")


def shadow() -> str:
    body = """  <ellipse cx="96" cy="107" rx="64" ry="7" fill="#6B8F4E" fill-opacity="0.26"/>"""
    return svg((30, 98, 132, 18), body, "", "Cien lisa. Zostaje na ziemi, gdy lis skacze.")


# nazwa czesci -> (funkcja, ramka viewBox, punkt obrotu w ukladzie fox.svg)
PARTS = {
    "rear": (rear, (40, 36, 72, 56), JOINT),
    "front": (front, (82, 36, 72, 56), JOINT),
    "head": (head, (122, 0, 74, 76), NECK),
    "tail": (tail, (0, 20, 64, 50), TAIL_BASE),
    "leg": (leg, (-9, -8, 20, LEG_LEN + 16), (0.0, 0.0)),
    "shadow": (shadow, (30, 98, 132, 18), SHADOW),
}


def vec(p: tuple) -> str:
    return f"Vector2({p[0]:g}, {p[1]:g})"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    lines = [
        "class_name FoxRigData",
        "extends RefCounted",
        "## Ramki i punkty obrotu czesci lisa. PLIK GENEROWANY: tools/gen_fox.py.",
        "## Wspolrzedne w ukladzie starego fox.svg (196 x 116, lis patrzy w prawo).",
        "",
        f"const ORIGIN := {vec(ORIGIN)}",
        f"const JOINT := {vec(JOINT)}",
        f"const NECK := {vec(NECK)}",
        f"const TAIL_BASE := {vec(TAIL_BASE)}",
        f"const SHADOW := {vec(SHADOW)}",
        f"const LEG_LEN := {LEG_LEN:.1f}",
        "const HIPS := {",
    ]
    for name, point in HIPS.items():
        lines.append(f'\t"{name}": {vec(point)},')
    lines.append("}")
    lines.append("## nazwa -> [sciezka tekstury, srodek ramki, punkt obrotu]")
    lines.append("const PARTS := {")
    for name, (make, box, pivot) in PARTS.items():
        (OUT / f"fox_{name}.svg").write_text(make(), encoding="utf-8")
        center = (box[0] + box[2] / 2.0, box[1] + box[3] / 2.0)
        path = f"res://assets/sprites/animals/fox_parts/fox_{name}.svg"
        lines.append(f'\t"{name}": ["{path}", {vec(center)}, {vec(pivot)}],')
    lines.append("}")
    DATA.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"zapisano {len(PARTS)} czesci lisa do {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
