#!/usr/bin/env python3
"""Generuje tlo farmy (ground.svg) i przedni plot wybiegu (fence_front.svg).

Uruchomienie z katalogu projektu:  python3 tools/gen_ground.py
Uklad (wybieg, sciezki, strefy budynkow) musi zgadzac sie z data/buildings.json
i ze scena scenes/farm/farm.tscn.
"""
import random
from pathlib import Path

W, H = 1080, 2400
RUN = (120, 1090, 960, 1500)          # x0, y0, x1, y1 wybiegu
GATE = (480, 600)                     # przerwa w plocie (gora i dol)
OUTLINE = "#4b2e16"
OUT_DIR = Path(__file__).resolve().parent.parent / "assets/sprites/world"

# Strefy bez dekoracji: wybieg, sciezki, budynki (x0, y0, x1, y1).
BLOCKED = [
    (RUN[0] - 50, RUN[1] - 70, RUN[2] + 50, RUN[3] + 50),
    (160, 940, 920, 1070), (470, 1000, 610, 1100),
    (470, 1490, 610, H), (160, 2030, 920, 2160),
    (60, 520, 520, 990), (580, 540, 1010, 990),
    (30, 1600, 510, 2080), (560, 1610, 1040, 2080),
]


def free(x, y, pad=0):
    return not any(a - pad <= x <= c + pad and b - pad <= y <= d + pad for a, b, c, d in BLOCKED)


def post(x, y_base, wide=16, tall=52):
    return (f'<rect x="{x - wide / 2:g}" y="{y_base - tall:g}" width="{wide}" height="{tall}" rx="4" '
            f'fill="#fbf1da" stroke="{OUTLINE}" stroke-width="4"/>')


def rail(x0, x1, y):
    return (f'<rect x="{x0}" y="{y}" width="{x1 - x0}" height="10" rx="3" '
            f'fill="#f3e3bd" stroke="{OUTLINE}" stroke-width="3"/>')


def fence_row(y_base, post_xs):
    parts = []
    for x0, x1 in ((RUN[0], GATE[0]), (GATE[1], RUN[2])):
        parts += [rail(x0, x1, y_base - 40), rail(x0, x1, y_base - 20)]
    for x in post_xs:
        gate = x in GATE
        parts.append(post(x, y_base, 22 if gate else 16, 62 if gate else 52))
    return parts


def row_posts():
    xs = list(range(RUN[0], GATE[0] + 1, 60)) + list(range(GATE[1], RUN[2] + 1, 60))
    return xs


def ground():
    rnd = random.Random(7)
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
         '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
         '<stop offset="0" stop-color="#9bd866"/><stop offset="1" stop-color="#84c752"/>'
         '</linearGradient></defs>',
         f'<rect width="{W}" height="{H}" fill="url(#g)"/>']
    for y in range(0, H, 240):
        s.append(f'<rect x="0" y="{y}" width="{W}" height="120" fill="#ffffff" opacity="0.05"/>')
    for _ in range(14):
        x, y = rnd.randint(0, W), rnd.randint(0, H)
        s.append(f'<ellipse cx="{x}" cy="{y}" rx="{rnd.randint(90, 180)}" ry="{rnd.randint(40, 80)}" '
                 f'fill="#aee27a" opacity="0.35"/>')

    # sciezki
    d = "M230 1005H850M540 1005V1090M540 1500V2400M230 2095H850"
    s.append(f'<path d="{d}" fill="none" stroke="#c9a865" stroke-width="106" stroke-linecap="round"/>')
    s.append(f'<path d="{d}" fill="none" stroke="#ecd59c" stroke-width="88" stroke-linecap="round"/>')

    # wybieg
    x0, y0, x1, y1 = RUN
    s.append(f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" rx="36" '
             f'fill="#e6c98f" stroke="#c9a865" stroke-width="8"/>')
    for _ in range(70):
        x, y = rnd.randint(x0 + 30, x1 - 30), rnd.randint(y0 + 30, y1 - 30)
        col = rnd.choice(["#d6b574", "#f1dba8", "#cfae6e"])
        s.append(f'<ellipse cx="{x}" cy="{y}" rx="{rnd.randint(4, 10)}" ry="{rnd.randint(2, 5)}" fill="{col}"/>')
    for _ in range(8):
        x, y = rnd.randint(x0 + 60, x1 - 60), rnd.randint(y0 + 60, y1 - 40)
        s.append(f'<path d="M{x} {y}q-4 -14 -8 -2M{x} {y}q0 -18 2 -2M{x} {y}q6 -14 10 -2" '
                 f'fill="none" stroke="#8fbf58" stroke-width="4" stroke-linecap="round"/>')

    # dekoracje na trawie
    n = 0
    while n < 150:
        x, y = rnd.randint(10, W - 10), rnd.randint(10, H - 10)
        if free(x, y, 10):
            s.append(f'<path d="M{x} {y}q-4 -14 -8 -2M{x} {y}q0 -18 2 -2M{x} {y}q6 -14 10 -2" '
                     f'fill="none" stroke="#5fae3c" stroke-width="4" stroke-linecap="round"/>')
            n += 1
    n = 0
    while n < 46:
        x, y = rnd.randint(20, W - 20), rnd.randint(20, H - 20)
        if free(x, y, 20):
            col = rnd.choice(["#ffffff", "#ffd1e3", "#fff3a6", "#ffffff"])
            petals = "".join(f'<circle cx="{x + dx}" cy="{y + dy}" r="5" fill="{col}"/>'
                             for dx, dy in ((-5, 0), (5, 0), (0, -5), (0, 5)))
            s.append(petals + f'<circle cx="{x}" cy="{y}" r="4" fill="#f7a531"/>')
            n += 1
    n = 0
    while n < 12:
        x, y = rnd.randint(20, W - 20), rnd.randint(20, H - 20)
        if free(x, y, 30):
            s.append(f'<ellipse cx="{x}" cy="{y}" rx="{rnd.randint(10, 18)}" ry="{rnd.randint(7, 11)}" '
                     f'fill="#b8c0c4" stroke="{OUTLINE}" stroke-width="3"/>')
            n += 1

    # plot: boki i tyl (przod jest osobnym sprite'em, zeby zaslanial kury)
    for x in (x0, x1):
        s.append(f'<rect x="{x - 5}" y="{y0 - 30}" width="10" height="{y1 - y0 + 10}" rx="3" '
                 f'fill="#f3e3bd" stroke="{OUTLINE}" stroke-width="3"/>')
        for y in range(y0 + 68, y1 - 20, 68):
            s.append(post(x, y))
    s += fence_row(y0 + 8, row_posts())
    s.append('</svg>')
    return "\n".join(s)


def fence_front():
    # Lokalny uklad: podstawa plotu na y=66; sprite ma 1080 px szerokosci jak swiat.
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="72" viewBox="0 0 {W} 72">']
    s += fence_row(66, row_posts())
    s.append('</svg>')
    return "\n".join(s)


if __name__ == "__main__":
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "ground.svg").write_text(ground() + "\n")
    (OUT_DIR / "fence_front.svg").write_text(fence_front() + "\n")
    print("OK:", OUT_DIR)
