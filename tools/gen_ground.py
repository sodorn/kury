#!/usr/bin/env python3
"""Generuje tlo farmy (ground.svg) i przedni plot wybiegu (fence_front.svg).

Uruchomienie z katalogu projektu:  python3 tools/gen_ground.py
Uklad (wybieg, sciezki, strefy budynkow) musi zgadzac sie z farm.tscn.

Grafika 2.0: cieplejsza, z gradientami, plamami swiatla i wieksza iloscia
drobiazgow (kwiaty, grzyby, kamienie, motyle, kepki trawy w kilku odcieniach).
Bez filtrow SVG — Godot renderuje SVG przez ThorVG, ktory ich nie obsluguje.
"""
import random
from pathlib import Path

W, H = 1080, 2400
RUN = (120, 1090, 960, 1500)          # x0, y0, x1, y1 wybiegu
GATE = (480, 600)                     # przerwa w plocie (gora i dol)
OUTLINE = "#4A2D16"
OUT_DIR = Path(__file__).resolve().parent.parent / "assets/sprites/world"

# Strefy bez dekoracji: wybieg, sciezki, budynki (x0, y0, x1, y1).
BLOCKED = [
    (RUN[0] - 50, RUN[1] - 70, RUN[2] + 50, RUN[3] + 50),
    (160, 940, 920, 1070), (470, 1000, 610, 1100),
    (470, 1490, 610, H), (160, 2030, 920, 2160),
    (60, 520, 520, 990), (580, 540, 1010, 990),
    (30, 1600, 510, 2080), (560, 1610, 1040, 2080),
]

GRASS_TUFT = ("#4E9E32", "#5FAE3C", "#72BE४C".replace("४", "4"), "#8ACB5E")
FLOWER = (("#FFFFFF", "#F7C948"), ("#FFD9EC", "#F2748F"),
          ("#FFF6B0", "#F2A900"), ("#DCCBFF", "#8A6BD1"))


def free(x, y, pad=0):
    return not any(a - pad <= x <= c + pad and b - pad <= y <= d + pad for a, b, c, d in BLOCKED)


def defs():
    return f'''<defs>
<linearGradient id="grass" x1="0" y1="0" x2="0" y2="{H}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#9FDA6B"/>
  <stop offset="0.35" stop-color="#8BCE57"/>
  <stop offset="0.7" stop-color="#7CC24B"/>
  <stop offset="1" stop-color="#6EB441"/>
</linearGradient>
<radialGradient id="sun" cx="0.5" cy="0.5" r="0.5">
  <stop offset="0" stop-color="#FFF7C4" stop-opacity="0.5"/>
  <stop offset="0.6" stop-color="#FFF2A8" stop-opacity="0.18"/>
  <stop offset="1" stop-color="#FFF2A8" stop-opacity="0"/>
</radialGradient>
<radialGradient id="shade" cx="0.5" cy="0.5" r="0.5">
  <stop offset="0" stop-color="#3C8E2B" stop-opacity="0.28"/>
  <stop offset="1" stop-color="#3C8E2B" stop-opacity="0"/>
</radialGradient>
<linearGradient id="dirt" x1="0" y1="0" x2="0" y2="{H}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#F0D9A6"/>
  <stop offset="1" stop-color="#DFC287"/>
</linearGradient>
<linearGradient id="sand" x1="{RUN[0]}" y1="{RUN[1]}" x2="{RUN[2]}" y2="{RUN[3]}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#F0D6A0"/>
  <stop offset="0.5" stop-color="#E3C184"/>
  <stop offset="1" stop-color="#D2AC68"/>
</linearGradient>
<linearGradient id="post" x1="0" y1="0" x2="0" y2="62" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#FFF6DF"/>
  <stop offset="1" stop-color="#E4CFA4"/>
</linearGradient>
</defs>'''


def post(x, y_base, wide=16, tall=52):
    return (f'<rect x="{x - wide / 2:g}" y="{y_base - tall:g}" width="{wide}" height="{tall}" rx="6" '
            f'fill="url(#post)" stroke="{OUTLINE}" stroke-width="4"/>')


def rail(x0, x1, y):
    return (f'<rect x="{x0}" y="{y}" width="{x1 - x0}" height="11" rx="4" '
            f'fill="#F3E3BD" stroke="{OUTLINE}" stroke-width="3"/>')


def fence_row(y_base, post_xs):
    parts = []
    for x0, x1 in ((RUN[0], GATE[0]), (GATE[1], RUN[2])):
        parts += [rail(x0, x1, y_base - 40), rail(x0, x1, y_base - 20)]
    for x in post_xs:
        gate = x in GATE
        parts.append(post(x, y_base, 22 if gate else 16, 62 if gate else 52))
    return parts


def row_posts():
    return list(range(RUN[0], GATE[0] + 1, 60)) + list(range(GATE[1], RUN[2] + 1, 60))


def tuft(x, y, rnd):
    color = rnd.choice(GRASS_TUFT)
    scale = rnd.uniform(0.8, 1.45)
    w = 5 * scale
    return (f'<path d="M{x} {y}q{-4 * scale:.0f} {-15 * scale:.0f} {-8 * scale:.0f} {-2 * scale:.0f}'
            f'M{x} {y}q0 {-19 * scale:.0f} {2 * scale:.0f} {-2 * scale:.0f}'
            f'M{x} {y}q{6 * scale:.0f} {-15 * scale:.0f} {10 * scale:.0f} {-2 * scale:.0f}" '
            f'fill="none" stroke="{color}" stroke-width="{w:.1f}" stroke-linecap="round"/>')


def flower(x, y, rnd):
    petal, middle = rnd.choice(FLOWER)
    r = rnd.uniform(4.5, 6.5)
    d = r + 1
    out = [f'<circle cx="{x + dx * d:.0f}" cy="{y + dy * d:.0f}" r="{r:.1f}" fill="{petal}"/>'
           for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))]
    out.append(f'<circle cx="{x}" cy="{y}" r="{r * 0.75:.1f}" fill="{middle}"/>')
    out.append(f'<circle cx="{x - d:.0f}" cy="{y - 1}" r="{r * 0.3:.1f}" fill="#FFFFFF" fill-opacity="0.8"/>')
    return "".join(out)


def mushroom(x, y, rnd):
    h = rnd.uniform(0.85, 1.2)
    return (f'<g stroke="{OUTLINE}" stroke-width="3" stroke-linejoin="round">'
            f'<rect x="{x - 4:.0f}" y="{y - 12 * h:.0f}" width="8" height="{12 * h:.0f}" rx="4" fill="#FFF3DC"/>'
            f'<path d="M{x - 14:.0f} {y - 10 * h:.0f}a14 10 0 0 1 28 0Z" fill="#E8553F"/>'
            f'<circle cx="{x - 5:.0f}" cy="{y - 14 * h:.0f}" r="2.5" fill="#FFF3DC" stroke="none"/>'
            f'<circle cx="{x + 4:.0f}" cy="{y - 16 * h:.0f}" r="2" fill="#FFF3DC" stroke="none"/></g>')


def stone(x, y, rnd):
    rx = rnd.uniform(11, 19)
    ry = rx * rnd.uniform(0.55, 0.72)
    return (f'<g stroke="{OUTLINE}" stroke-width="3">'
            f'<ellipse cx="{x}" cy="{y}" rx="{rx:.0f}" ry="{ry:.0f}" fill="#BFC7CB"/>'
            f'<path d="M{x - rx * 0.6:.0f} {y - ry * 0.3:.0f}a{rx * 0.6:.0f} {ry * 0.5:.0f} 0 0 1 {rx * 0.7:.0f} {-ry * 0.4:.0f}" '
            f'fill="none" stroke="#E8EEF0" stroke-width="4"/></g>')


def butterfly(x, y, rnd):
    col = rnd.choice(("#FFD152", "#FF9BC2", "#9BD8FF"))
    return (f'<g stroke="{OUTLINE}" stroke-width="2.5">'
            f'<ellipse cx="{x - 7}" cy="{y - 3}" rx="8" ry="10" fill="{col}" transform="rotate(-20 {x - 7} {y - 3})"/>'
            f'<ellipse cx="{x + 7}" cy="{y - 3}" rx="8" ry="10" fill="{col}" transform="rotate(20 {x + 7} {y - 3})"/>'
            f'<rect x="{x - 2}" y="{y - 8}" width="4" height="16" rx="2" fill="{OUTLINE}" stroke="none"/></g>')


def scatter(rnd, count, pad, step=120):
    """Punkty rozlozone rownomiernie: siatka z losowym przesunieciem w komorce."""
    cells = []
    for gy in range(0, H, step):
        for gx in range(0, W, step):
            x = gx + rnd.randint(8, step - 8)
            y = gy + rnd.randint(8, step - 8)
            if 10 <= x <= W - 10 and 10 <= y <= H - 10 and free(x, y, pad):
                cells.append((x, y))
    rnd.shuffle(cells)
    return cells[:count]


def feeder(x, y):
    """Podluzny karmnik z ziarnem."""
    return (f'<g stroke="{OUTLINE}" stroke-width="5" stroke-linejoin="round">'
            f'<ellipse cx="{x}" cy="{y + 26}" rx="62" ry="14" fill="#2d4a18" fill-opacity="0.22" stroke="none"/>'
            f'<path d="M{x - 56} {y - 14}h112l-12 40h-88Z" fill="#C98A52"/>'
            f'<path d="M{x - 56} {y - 14}h112l-6 14h-100Z" fill="#E0A96A"/>'
            f'<g stroke="#8A5A2B" stroke-width="3">'
            f'<ellipse cx="{x - 24}" cy="{y - 6}" rx="6" ry="4" fill="#F2C94C"/>'
            f'<ellipse cx="{x - 4}" cy="{y - 2}" rx="6" ry="4" fill="#F7D96E"/>'
            f'<ellipse cx="{x + 20}" cy="{y - 6}" rx="6" ry="4" fill="#F2C94C"/>'
            f'<ellipse cx="{x + 36}" cy="{y - 1}" rx="6" ry="4" fill="#F7D96E"/>'
            f'</g></g>')


def waterer(x, y):
    """Miska z woda."""
    return (f'<g stroke="{OUTLINE}" stroke-width="5" stroke-linejoin="round">'
            f'<ellipse cx="{x}" cy="{y + 24}" rx="46" ry="12" fill="#2d4a18" fill-opacity="0.22" stroke="none"/>'
            f'<path d="M{x - 42} {y - 10}h84l-10 34h-64Z" fill="#9FB4C0"/>'
            f'<ellipse cx="{x}" cy="{y - 10}" rx="42" ry="13" fill="#79C8E8"/>'
            f'<ellipse cx="{x}" cy="{y - 10}" rx="42" ry="13" fill="none"/>'
            f'<path d="M{x - 26} {y - 14}a26 9 0 0 1 24 -4" fill="none" stroke="#DCF4FF" stroke-width="5"/>'
            f'</g>')


def ground():
    rnd = random.Random(11)
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
         defs(),
         f'<rect width="{W}" height="{H}" fill="url(#grass)"/>']

    # duze plamy swiatla i cienia
    for _ in range(16):
        x, y = rnd.randint(-100, W + 100), rnd.randint(0, H)
        rx, ry = rnd.randint(170, 330), rnd.randint(90, 180)
        kind = "sun" if rnd.random() < 0.55 else "shade"
        s.append(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="url(#{kind})"/>')

    # sciezki
    d = "M230 1005H850M540 1005V1090M540 1500V2400M230 2095H850"
    s.append(f'<path d="{d}" fill="none" stroke="#C4A063" stroke-width="112" stroke-linecap="round" stroke-opacity="0.55"/>')
    s.append(f'<path d="{d}" fill="none" stroke="url(#dirt)" stroke-width="92" stroke-linecap="round"/>')
    for _ in range(90):
        if rnd.random() < 0.5:
            x, y = rnd.randint(250, 830), rnd.choice([rnd.randint(975, 1035), rnd.randint(2065, 2125)])
        else:
            x, y = rnd.randint(510, 570), rnd.choice([rnd.randint(1005, 1090), rnd.randint(1500, 2390)])
        s.append(f'<ellipse cx="{x}" cy="{y}" rx="{rnd.randint(3, 7)}" ry="{rnd.randint(2, 4)}" '
                 f'fill="#B8934F" fill-opacity="0.5"/>')

    # wybieg
    x0, y0, x1, y1 = RUN
    s.append(f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" rx="42" '
             f'fill="url(#sand)" stroke="#BE9A5C" stroke-width="8"/>')
    for _ in range(90):
        x, y = rnd.randint(x0 + 30, x1 - 30), rnd.randint(y0 + 30, y1 - 30)
        col = rnd.choice(("#D8B678", "#F3DEAE", "#CBA564", "#E9CF97"))
        s.append(f'<ellipse cx="{x}" cy="{y}" rx="{rnd.randint(4, 11)}" ry="{rnd.randint(2, 6)}" fill="{col}"/>')
    for _ in range(14):  # zdzbla siana
        x, y = rnd.randint(x0 + 60, x1 - 60), rnd.randint(y0 + 60, y1 - 40)
        a = rnd.randint(-40, 40)
        s.append(f'<g transform="rotate({a} {x} {y})"><rect x="{x - 14}" y="{y - 2}" width="28" height="4" rx="2" '
                 f'fill="#E8C66A" fill-opacity="0.9"/></g>')
    for _ in range(9):
        x, y = rnd.randint(x0 + 60, x1 - 60), rnd.randint(y0 + 60, y1 - 40)
        s.append(tuft(x, y, rnd).replace('stroke="#4E9E32"', 'stroke="#9FC46A"'))

    # kamyki wzdluz sciezek
    for y in (1005, 2095):
        for x in range(250, 840, 46):
            for side, off in ((-1, 52), (1, 52)):
                if rnd.random() < 0.5:
                    s.append(f'<ellipse cx="{x + rnd.randint(-8, 8)}" cy="{y + side * off:.0f}" '
                             f'rx="{rnd.randint(5, 9)}" ry="{rnd.randint(3, 5)}" fill="#C2A469" fill-opacity="0.75"/>')

    # dekoracje na trawie, rozlozone rownomiernie po calej mapie
    for x, y in scatter(rnd, 170, 10, step=100):
        s.append(tuft(x, y, rnd))
    for x, y in scatter(rnd, 46, 22, step=170):
        s.append(flower(x, y, rnd))
    for x, y in scatter(rnd, 12, 30, step=330):
        s.append(stone(x, y, rnd))
    for x, y in scatter(rnd, 10, 30, step=360):
        s.append(mushroom(x, y, rnd))
    for x, y in scatter(rnd, 5, 40, step=520):
        s.append(butterfly(x, y, rnd))

    # karmnik i poidlo
    s.append(feeder(250, 1180))
    s.append(waterer(860, 1180))

    # plot: boki i tyl (przod jest osobnym sprite'em, zeby zaslanial kury)
    for x in (x0, x1):
        s.append(f'<rect x="{x - 5}" y="{y0 - 30}" width="11" height="{y1 - y0 + 10}" rx="4" '
                 f'fill="#F3E3BD" stroke="{OUTLINE}" stroke-width="3"/>')
        for y in range(y0 + 68, y1 - 20, 68):
            s.append(post(x, y))
    s += fence_row(y0 + 8, row_posts())
    s.append('</svg>')
    return "\n".join(s)


def fence_front():
    # Lokalny uklad: podstawa plotu na y=66; sprite ma szerokosc swiata.
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="72" viewBox="0 0 {W} 72">',
         defs()]
    s += fence_row(66, row_posts())
    s.append('</svg>')
    return "\n".join(s)


if __name__ == "__main__":
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "ground.svg").write_text(ground() + "\n")
    (OUT_DIR / "fence_front.svg").write_text(fence_front() + "\n")
    print("OK:", OUT_DIR)
