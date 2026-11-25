#!/usr/bin/env python3
"""Generuje malowane portrety ras do okienka "nowa rasa" i kart sklepu.

Wlasciciel (25.11): obrazki ras maja byc wieksze od postaci z wybiegu
i inne - bardziej artystyczne, oparte na tym, jak te kury naprawde
wygladaja. Pastelowy obraz, ale zywy: gruby tusz i plaskie cienie jak
postaci z Borderlands, malowane tla jak w Icewind Dale.

Jak to dziala:
  1. Dla kazdej rasy skladamy SVG z czesci: tlo (niebo, gory, charakterystyczny
     punkt krajobrazu z kraju pochodzenia), potem kogut z parametrow rasy:
     grzebien, czub, broda, opierzone nogi, goly kark, kedzierzawe piora,
     brak ogona, ogon na kilka metrow, wzor piora (obwodka, cetki, kreski).
  2. Kazda czesc ma tusz, cien w kolorze (polksiezyc przesuniety w dol)
     i kreskowanie w cieniu. Plamy koloru przechodza przez filtr
     feTurbulence + feDisplacementMap - brzegi wygladaja jak pociagniecia
     pedzla.
  3. rsvg-convert rasteryzuje SVG, a PIL dokłada ziarno papieru, winiete
     i lekko ociepla kolory. Wynik: assets/portraits/<id>.webp, 720x720.

Uruchomienie:  python3 tools/gen_portraits.py [id ...]
Wymaga: rsvg-convert (librsvg), Pillow, numpy.
"""

import math
import os
import random
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "portraits")
SIZE = 720
INK = "#2B1D18"

# ---------------------------------------------------------------------------
# geometria
# ---------------------------------------------------------------------------


def catmull(points, closed=True, tension=0.5):
    """Gladka krzywa przez punkty (Catmull-Rom -> Bezier). Zwraca 'd'."""
    pts = list(points)
    n = len(pts)
    if n < 2:
        return ""
    d = "M%.1f %.1f" % pts[0]
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if closed or i > 0 else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed or i + 2 < n else pts[(i + 1) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) * tension / 3.0, p1[1] + (p2[1] - p0[1]) * tension / 3.0)
        c2 = (p2[0] - (p3[0] - p1[0]) * tension / 3.0, p2[1] - (p3[1] - p1[1]) * tension / 3.0)
        d += " C%.1f %.1f %.1f %.1f %.1f %.1f" % (c1 + c2 + p2)
    if closed:
        d += " Z"
    return d


def shift(points, dx, dy):
    return [(x + dx, y + dy) for x, y in points]


def transform(points, sx=1.0, sy=1.0, rot=0.0, cx=0.0, cy=0.0, dx=0.0, dy=0.0):
    out = []
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    for x, y in points:
        x, y = (x - cx) * sx, (y - cy) * sy
        x, y = x * c - y * s, x * s + y * c
        out.append((x + cx + dx, y + cy + dy))
    return out


def feather(base, tip, width, bend=0.0, tip_round=0.15):
    """Pioro w ksztalcie liscia od nasady do czubka. bend wygina je w bok."""
    bx, by = base
    tx, ty = tip
    vx, vy = tx - bx, ty - by
    length = math.hypot(vx, vy) or 1.0
    nx, ny = -vy / length, vx / length
    mx, my = bx + vx * 0.45 + nx * bend * length, by + vy * 0.45 + ny * bend * length
    w = width
    a1 = (mx + nx * w, my + ny * w)
    a2 = (mx - nx * w, my - ny * w)
    t1 = (tx + nx * w * tip_round - vx / length * w * 0.6, ty + ny * w * tip_round - vy / length * w * 0.6)
    t2 = (tx - nx * w * tip_round - vx / length * w * 0.6, ty - ny * w * tip_round - vy / length * w * 0.6)
    return ("M%.1f %.1f Q%.1f %.1f %.1f %.1f Q%.1f %.1f %.1f %.1f Q%.1f %.1f %.1f %.1f Z"
            % (bx, by, a1[0], a1[1], t1[0], t1[1], tx, ty, t2[0], t2[1], a2[0], a2[1], bx, by))


def sickle(base, tip, width, curl):
    """Dlugie zakrzywione pioro ogona (sierp). curl > 0 wygina w gore."""
    bx, by = base
    tx, ty = tip
    vx, vy = tx - bx, ty - by
    length = math.hypot(vx, vy) or 1.0
    nx, ny = -vy / length, vx / length
    c1 = (bx + vx * 0.3 + nx * curl * length, by + vy * 0.3 + ny * curl * length)
    c2 = (bx + vx * 0.75 + nx * curl * length * 0.9, by + vy * 0.75 + ny * curl * length * 0.9)
    w = width
    return ("M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f Z" % (
        bx + nx * w, by + ny * w,
        c1[0] + nx * w, c1[1] + ny * w, c2[0] + nx * w * 0.5, c2[1] + ny * w * 0.5, tx, ty,
        c2[0] - nx * w * 0.4, c2[1] - ny * w * 0.4, c1[0] - nx * w * 0.9, c1[1] - ny * w * 0.9,
        bx - nx * w, by - ny * w))


# ---------------------------------------------------------------------------
# kolory
# ---------------------------------------------------------------------------


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgb_hex(c):
    return "#%02X%02X%02X" % tuple(max(0, min(255, int(round(v)))) for v in c)


def mix(a, b, t):
    ca, cb = hex_rgb(a), hex_rgb(b)
    return rgb_hex([ca[i] + (cb[i] - ca[i]) * t for i in range(3)])


def shade(c, t):
    """Cien w kolorze: ciemniej i chlodniej (w strone fioletu), nie w szarosc."""
    return mix(c, "#3A2E5C", t)


def light(c, t):
    return mix(c, "#FFF6E0", t)


# ---------------------------------------------------------------------------
# skladanie SVG
# ---------------------------------------------------------------------------


class Svg:
    def __init__(self, seed):
        self.defs = []
        self.body = []
        self.n = 0
        self.rand = random.Random(seed)

    def uid(self, prefix):
        self.n += 1
        return "%s%d" % (prefix, self.n)

    def add(self, s):
        self.body.append(s)

    def clip(self, d, evenodd=False):
        cid = self.uid("c")
        rule = ' clip-rule="evenodd"' if evenodd else ""
        self.defs.append('<clipPath id="%s"><path d="%s"%s/></clipPath>' % (cid, d, rule))
        return cid

    def lin(self, stops, x1=0, y1=0, x2=0, y2=1):
        gid = self.uid("g")
        s = "".join('<stop offset="%.2f" stop-color="%s" stop-opacity="%.2f"/>' % (o, c, a)
                    for o, c, a in stops)
        self.defs.append('<linearGradient id="%s" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>'
                         % (gid, x1, y1, x2, y2, s))
        return gid

    def rad(self, stops, cx=0.5, cy=0.5, r=0.5):
        gid = self.uid("r")
        s = "".join('<stop offset="%.2f" stop-color="%s" stop-opacity="%.2f"/>' % (o, c, a)
                    for o, c, a in stops)
        self.defs.append('<radialGradient id="%s" cx="%s" cy="%s" r="%s">%s</radialGradient>'
                         % (gid, cx, cy, r, s))
        return gid

    def render(self, frame=(110, 70, 480)):
        filters = """
<filter id="brush" x="-8%" y="-8%" width="116%" height="116%">
  <feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="3" seed="7" result="n"/>
  <feDisplacementMap in="SourceGraphic" in2="n" scale="9" xChannelSelector="R" yChannelSelector="G"/>
</filter>
<filter id="soft" x="-8%" y="-8%" width="116%" height="116%">
  <feTurbulence type="fractalNoise" baseFrequency="0.02" numOctaves="3" seed="11" result="n"/>
  <feDisplacementMap in="SourceGraphic" in2="n" scale="22" xChannelSelector="R" yChannelSelector="G" result="d"/>
  <feGaussianBlur in="d" stdDeviation="1.6"/>
</filter>
<filter id="wobble" x="-5%" y="-5%" width="110%" height="110%">
  <feTurbulence type="fractalNoise" baseFrequency="0.06" numOctaves="2" seed="3" result="n"/>
  <feDisplacementMap in="SourceGraphic" in2="n" scale="3.2" xChannelSelector="R" yChannelSelector="G"/>
</filter>
<filter id="grain" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="5" result="n"/>
  <feColorMatrix in="n" type="matrix" values="0 0 0 0 0.2  0 0 0 0 0.15  0 0 0 0 0.3  0 0 0 0.55 -0.12"/>
  <feComposite in2="SourceGraphic" operator="in"/>
</filter>"""
        x, y, w = frame
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600" viewBox="%d %d %d %d">'
                '<defs>%s%s</defs>%s</svg>' % (x, y, w, w, filters, "".join(self.defs), "".join(self.body)))


def painted(svg, d, color, shadow=None, hi=None, ink=4.0, sdx=10, sdy=14, hatch=True,
            texture=True, ink_color=INK, opacity=1.0):
    """Czesc ciala: plama koloru (pedzel), cien-polksiezyc, swiatlo, kreskowanie, tusz."""
    shadow = shadow or shade(color, 0.38)
    hi = hi or light(color, 0.45)
    cid = svg.clip(d)
    # Plama koloru wychodzi troche poza kontur (pedzel), ale przycinamy ja
    # konturem powiekszonym o pol grubosci tuszu - stad clip na samym tuszu.
    svg.add('<g clip-path="url(#%s)" opacity="%.2f">' % (cid, opacity))
    svg.add('<g filter="url(#brush)"><path d="%s" fill="%s" stroke="%s" stroke-width="12"/></g>'
            % (d, color, color))
    svg.add('</g>')
    sh_id = svg.uid("p")
    svg.defs.append('<path id="%s" d="%s"/>' % (sh_id, d))
    # Swiatlo i cien robimy maska z przesunietej kopii.
    hl = svg.uid("m")
    svg.defs.append('<mask id="%s"><rect x="-50" y="-50" width="700" height="700" fill="white"/>'
                    '<use href="#%s" transform="translate(%d %d)" fill="black"/></mask>'
                    % (hl, sh_id, sdx * 0.7, sdy * 0.7))
    sm = svg.uid("m")
    svg.defs.append('<mask id="%s"><rect x="-50" y="-50" width="700" height="700" fill="white"/>'
                    '<use href="#%s" transform="translate(%d %d)" fill="black"/></mask>'
                    % (sm, sh_id, -sdx, -sdy))
    svg.add('<g clip-path="url(#%s)">' % cid)
    # 1) rozjasnienie przy lewej gornej krawedzi
    svg.add('<g mask="url(#%s)" filter="url(#brush)"><path d="%s" fill="%s" opacity="0.75"/></g>'
            % (hl, d, hi))
    # 2) cien przy prawej dolnej krawedzi
    svg.add('<g mask="url(#%s)" filter="url(#brush)"><path d="%s" fill="%s" opacity="0.92"/></g>'
            % (sm, d, shadow))
    if hatch:
        lines = []
        for i in range(-40, 70):
            x = i * 9.0
            lines.append("M%.1f %.1f L%.1f %.1f" % (x, 0, x + 600, 600))
        svg.add('<g mask="url(#%s)" filter="url(#wobble)"><path d="%s" stroke="%s" stroke-width="1.6" '
                'opacity="0.38" fill="none"/></g>' % (sm, " ".join(lines), shade(shadow, 0.5)))
    if texture:
        svg.add('<rect x="0" y="0" width="600" height="600" filter="url(#grain)" fill="#000" opacity="0.5"/>')
    svg.add('</g>')
    if ink > 0:
        svg.add('<g filter="url(#wobble)"><path d="%s" fill="none" stroke="%s" stroke-width="%.1f" '
                'stroke-linejoin="round" stroke-linecap="round"/></g>' % (d, ink_color, ink))
    return cid


def ink_line(svg, d, width=3.0, color=INK, opacity=1.0):
    svg.add('<g filter="url(#wobble)"><path d="%s" fill="none" stroke="%s" stroke-width="%.1f" '
            'stroke-linecap="round" stroke-linejoin="round" opacity="%.2f"/></g>' % (d, color, width, opacity))


# ---------------------------------------------------------------------------
# tla
# ---------------------------------------------------------------------------


def background(svg, b):
    bg = b["bg"]
    sky = svg.lin([(0, bg["sky"][0], 1), (1, bg["sky"][1], 1)])
    svg.add('<rect x="-60" y="-60" width="720" height="720" fill="url(#%s)"/>' % sky)
    sun = svg.rad([(0, bg.get("sun", "#FFF3D0"), 0.95), (1, bg.get("sun", "#FFF3D0"), 0)], r=0.5)
    sx, sy = bg.get("sun_pos", (150, 150))
    svg.add('<circle cx="%d" cy="%d" r="190" fill="url(#%s)"/>' % (sx, sy, sun))
    rnd = svg.rand
    # Chmury jak pociagniecia pedzla.
    svg.add('<g filter="url(#soft)" opacity="0.55">')
    for i in range(7):
        cx, cy = rnd.uniform(0, 600), rnd.uniform(40, 220)
        svg.add('<ellipse cx="%.0f" cy="%.0f" rx="%.0f" ry="%.0f" fill="%s"/>'
                % (cx, cy, rnd.uniform(60, 130), rnd.uniform(12, 26), light(bg["sky"][0], 0.6)))
    svg.add('</g>')
    # Pasma gor / wzgorz.
    layers = bg["hills"]
    for li, color in enumerate(layers):
        base = 300 + li * 55
        pts = [(-40, 640)]
        x = -40
        while x < 680:
            amp = bg.get("peaks", 40) * (1.0 - li * 0.25)
            pts.append((x, base - rnd.uniform(0.2, 1.0) * amp))
            x += rnd.uniform(70, 140)
        pts.append((680, 640))
        d = catmull(pts, closed=True, tension=0.45)
        svg.add('<g filter="url(#soft)"><path d="%s" fill="%s"/></g>' % (d, color))
        if li == 0 and bg.get("snow"):
            svg.add('<g filter="url(#soft)" opacity="0.7"><path d="%s" fill="#FFFFFF" '
                    'transform="translate(0 6)" clip-path="url(#%s)"/></g>' % (d, svg.clip(
                        "M-40 0 L680 0 L680 %d L-40 %d Z" % (base - 10, base - 10))))
    landmark(svg, b)
    # Ziemia i trawa.
    ground = bg["ground"]
    gd = catmull([(-40, 470), (150, 455), (330, 468), (480, 452), (640, 466), (640, 640), (-40, 640)],
                 closed=True)
    svg.add('<g filter="url(#soft)"><path d="%s" fill="%s"/></g>' % (gd, ground))
    strokes = []
    for i in range(140):
        x = rnd.uniform(-10, 610)
        y = rnd.uniform(470, 600)
        h = rnd.uniform(10, 26)
        strokes.append('<path d="M%.0f %.0f q %.0f %.0f %.0f %.0f" stroke="%s" stroke-width="%.1f" '
                       'fill="none" stroke-linecap="round" opacity="%.2f"/>'
                       % (x, y, rnd.uniform(-4, 4), -h * 0.6, rnd.uniform(-8, 8), -h,
                          rnd.choice([shade(ground, 0.25), light(ground, 0.3), shade(ground, 0.12)]),
                          rnd.uniform(1.5, 3.2), rnd.uniform(0.35, 0.8)))
    svg.add('<g filter="url(#wobble)">%s</g>' % "".join(strokes))
    # Cien pod ptakiem.
    sh = svg.rad([(0, "#2A1E30", 0.45), (1, "#2A1E30", 0)])
    svg.add('<ellipse cx="%d" cy="512" rx="%d" ry="26" fill="url(#%s)"/>' % (b.get("shadow_x", 330), 160, sh))


def landmark(svg, b):
    kind = b["bg"].get("landmark")
    c = b["bg"].get("lm_color", "#8A7A9A")
    out = []
    if kind == "cypress":
        for x, h in [(470, 150), (500, 120), (110, 135)]:
            out.append('<path d="%s" fill="%s"/>' % (catmull([(x, 420 - h), (x + 14, 400 - h * 0.4),
                                                              (x + 10, 440), (x - 10, 440),
                                                              (x - 14, 400 - h * 0.4)]), c))
        out.append('<path d="M60 430 L110 395 L170 430 Z" fill="%s"/>' % mix(c, "#C9A27A", 0.5))
    elif kind == "barn":
        out.append('<path d="M450 440 L450 370 L490 335 L530 370 L530 440 Z" fill="%s"/>' % c)
        out.append('<path d="M440 375 L490 330 L540 375" stroke="%s" stroke-width="8" fill="none"/>'
                   % shade(c, 0.3))
        out.append('<rect x="80" y="395" width="16" height="45" fill="%s"/>' % shade(c, 0.2))
    elif kind == "castle":
        out.append('<path d="M455 440 L455 360 L470 360 L470 330 L480 300 L490 330 L490 360 L510 360 '
                   'L510 345 L525 320 L540 345 L540 440 Z" fill="%s"/>' % c)
    elif kind == "boats":
        out.append('<rect x="-10" y="420" width="620" height="40" fill="%s" opacity="0.7"/>'
                   % b["bg"].get("sea", "#9CC3D4"))
        for x in (440, 520):
            out.append('<path d="M%d 430 L%d 430 L%d 445 L%d 445 Z" fill="%s"/>' % (x, x + 60, x + 50, x + 10, c))
            out.append('<path d="M%d 428 L%d 370 L%d 428 Z" fill="%s"/>' % (x + 30, x + 30, x + 56,
                                                                             light(c, 0.7)))
    elif kind == "andes":
        pass
    elif kind == "misty":
        out.append('<path d="M420 440 L440 330 L460 440 Z" fill="%s" opacity="0.6"/>' % c)
        out.append('<path d="M470 440 L500 300 L530 440 Z" fill="%s" opacity="0.5"/>' % c)
    elif kind == "palms":
        for x in (470, 525):
            out.append('<path d="M%d 445 Q %d 390 %d 340" stroke="%s" stroke-width="7" fill="none"/>'
                       % (x, x - 6, x + 10, c))
            for a in range(0, 360, 60):
                ex = x + 10 + math.cos(math.radians(a)) * 38
                ey = 340 + math.sin(math.radians(a)) * 16
                out.append('<path d="M%d 340 Q %.0f %.0f %.0f %.0f" stroke="%s" stroke-width="6" '
                           'fill="none" stroke-linecap="round"/>' % (x + 10, (x + 10 + ex) / 2, 325, ex, ey, c))
    elif kind == "garden":
        for x in (450, 505, 90):
            out.append('<circle cx="%d" cy="405" r="34" fill="%s"/>' % (x, c))
        out.append('<rect x="470" y="395" width="70" height="50" fill="%s"/>' % light(c, 0.5))
    elif kind == "windmill":
        out.append('<path d="M480 445 L488 360 L512 360 L520 445 Z" fill="%s"/>' % c)
        for a in (20, 110, 200, 290):
            ex = 500 + math.cos(math.radians(a)) * 70
            ey = 360 + math.sin(math.radians(a)) * 70
            out.append('<path d="M500 360 L%.0f %.0f" stroke="%s" stroke-width="9"/>' % (ex, ey, shade(c, 0.2)))
    elif kind == "church":
        out.append('<rect x="460" y="370" width="70" height="75" fill="%s"/>' % c)
        out.append('<path d="M480 370 Q 495 320 495 300 Q 495 320 510 370 Z" fill="%s"/>' % mix(c, "#D9A441", 0.6))
        out.append('<path d="M478 372 Q 495 330 512 372 Z" fill="%s"/>' % mix(c, "#C8913C", 0.5))
        out.append('<path d="M495 300 L495 282 M488 290 L502 290" stroke="%s" stroke-width="3"/>'
                   % mix(c, "#D9A441", 0.6))
    elif kind == "forest":
        for x in (430, 470, 510, 550, 90, 60):
            out.append('<path d="M%d 330 L%d 445 L%d 445 Z" fill="%s"/>' % (x, x - 28, x + 28, c))
    elif kind == "timber":
        out.append('<path d="M440 445 L440 385 L495 345 L550 385 L550 445 Z" fill="%s"/>' % light(c, 0.55))
        out.append('<path d="M440 385 L495 345 L550 385 M440 410 L550 410 M470 385 L470 445 M520 385 '
                   'L520 445 M440 445 L470 410 M550 445 L520 410" stroke="%s" stroke-width="5" fill="none"/>'
                   % shade(c, 0.2))
    elif kind == "domes":
        out.append('<rect x="430" y="390" width="140" height="55" fill="%s"/>' % c)
        out.append('<path d="M460 390 Q 500 320 540 390 Z" fill="%s"/>' % c)
        for x in (425, 575):
            out.append('<path d="M%d 445 L%d 300 L%d 280 L%d 300 L%d 445 Z" fill="%s"/>'
                       % (x - 5, x - 5, x, x + 5, x + 5, c))
    elif kind == "torii":
        r = "#D2553F"
        out.append('<path d="M455 445 L462 360 M535 445 L528 360" stroke="%s" stroke-width="11"/>' % r)
        out.append('<path d="M440 360 Q 495 345 550 360 L552 350 Q 495 333 438 350 Z" fill="%s"/>' % r)
        out.append('<rect x="452" y="372" width="86" height="9" fill="%s"/>' % r)
    elif kind == "terraces":
        for i, y in enumerate((395, 415, 435)):
            out.append('<path d="M380 %d Q 480 %d 620 %d L620 %d L380 %d Z" fill="%s"/>'
                       % (y, y - 12, y, y + 20, y + 20, mix(c, "#B9D98A", 0.2 * i)))
        for x in (70, 95):
            out.append('<path d="M%d 445 L%d 330" stroke="%s" stroke-width="6"/>' % (x, x + 4, shade(c, 0.2)))
    elif kind == "volcano":
        out.append('<path d="M380 445 L470 300 L500 300 L600 445 Z" fill="%s"/>' % c)
        out.append('<g filter="url(#soft)" opacity="0.5"><ellipse cx="485" cy="270" rx="50" ry="22" '
                   'fill="#EED7F0"/></g>')
    if out:
        svg.add('<g filter="url(#soft)" opacity="0.92">%s</g>' % "".join(out))


# ---------------------------------------------------------------------------
# kogut
# ---------------------------------------------------------------------------

BODY = [(205, 335), (225, 288), (290, 268), (370, 276), (432, 302), (448, 345), (424, 398),
        (362, 438), (292, 446), (232, 418), (206, 378)]


def bird(svg, b):
    k = b.get("pose", {})
    sx, sy = k.get("sx", 1.0), k.get("sy", 1.0)
    rot = k.get("rot", 0.0)
    cx, cy = 330, 360
    dy = k.get("dy", 0.0)

    def T(points):
        return transform(points, sx, sy, rot, cx, cy, 0, dy)

    def TP(p):
        return T([p])[0]

    c_body = b["body"]
    c_hackle = b.get("hackle", c_body)
    c_wing = b.get("wing", c_body)
    c_tail = b.get("tail_color", shade(c_body, 0.3))
    c_breast = b.get("breast", c_body)
    c_leg = b.get("leg", "#E8B84A")
    c_comb = b.get("comb_color", "#D8322C")
    rnd = svg.rand

    # --- noga z tylu -------------------------------------------------------
    legs(svg, b, T, far=True)

    # --- ogon ---------------------------------------------------------------
    tail(svg, b, T, c_tail)

    # --- tulow ---------------------------------------------------------------
    body_src = BODY
    if b.get("tail") == "none":
        # Bez kupra: grzbiet opada lagodnie w dol, bez schodka po ogonie.
        body_src = [(205, 335), (225, 288), (290, 266), (360, 276), (414, 306), (436, 346), (418, 394),
                    (362, 436), (292, 446), (232, 418), (206, 378)]
    body_pts = T(body_src)
    body_d = cloud(body_pts, 30, rnd=rnd) if b.get("fluffy") else catmull(body_pts)
    cid = painted(svg, body_d, c_body)
    # Piers innego koloru (np. czarna u feniksa).
    if c_breast != c_body:
        breast = T([(200, 330), (240, 300), (290, 330), (300, 400), (270, 440), (222, 420), (204, 380)])
        svg.add('<g clip-path="url(#%s)" filter="url(#brush)"><path d="%s" fill="%s" opacity="0.95"/></g>'
                % (cid, catmull(breast), c_breast))
    pattern(svg, b, cid, T)
    if b.get("frizzle"):
        frizzle(svg, b, T, body_pts)

    # --- siodlo (piora na krzyzu) -------------------------------------------
    if b.get("saddle", True) and not b.get("fluffy"):
        sad_col = b.get("saddle_color", c_hackle)
        for i in range(9):
            t = i / 8.0
            base = TP((360 + t * 50, 290 + t * 8))
            tip = TP((395 + t * 55 + b.get("saddle_len", 0) * 0.5, 350 + t * 12 + b.get("saddle_len", 0)))
            painted(svg, feather(base, tip, 9, bend=0.05), sad_col if i % 2 else light(sad_col, 0.12),
                    ink=2.2, sdx=4, sdy=5, hatch=False, texture=False)

    # --- skrzydlo ------------------------------------------------------------
    # Lotki (spod skrzydla, ku tylowi), na nie pokrywy w ksztalcie lzy.
    if not b.get("fluffy"):
        for i in range(6):
            t = i / 5.0
            root = TP((318 + t * 52, 352 + t * 4))
            tip = TP((388 + t * 34, 384 - t * 10))
            painted(svg, feather(root, tip, 10, bend=0.04), shade(c_wing, 0.1 + 0.05 * (i % 2)),
                    ink=2.0, sdx=4, sdy=5, hatch=False, texture=False)
    wing_pts = T([(258, 322), (300, 300), (360, 306), (412, 328), (424, 350), (380, 362), (318, 368),
                  (274, 356)])
    if b.get("fluffy"):
        # Jedwabista chowa skrzydlo w puchu: tylko kilka luczkow.
        for i in range(4):
            p = TP((300 + i * 26, 336 + (i % 2) * 6))
            ink_line(svg, "M%.1f %.1f a 14 10 0 0 0 26 0" % (p[0] - 13, p[1]), 2.0, shade(c_wing, 0.5), 0.6)
        wid = None
    else:
        wid = painted(svg, catmull(wing_pts), c_wing, sdx=7, sdy=9)
    if not b.get("fluffy"):
        rows = []
        for r in range(3):
            for i in range(7 - r):
                x = 280 + i * 18 + r * 14
                y = 318 + r * 14
                p = TP((x, y))
                rows.append('<path d="M%.1f %.1f q 9 10 18 0" stroke="%s" stroke-width="2" fill="none" '
                            'opacity="0.55"/>' % (p[0] - 9, p[1], shade(c_wing, 0.6)))
        svg.add('<g clip-path="url(#%s)" filter="url(#wobble)">%s</g>' % (wid, "".join(rows)))
        if b.get("wing_bar"):
            bar = T([(290, 346), (340, 342), (396, 348), (398, 355), (340, 352), (292, 356)])
            svg.add('<g clip-path="url(#%s)" filter="url(#brush)"><path d="%s" fill="%s" opacity="0.7"/></g>'
                    % (wid, catmull(bar), b["wing_bar"]))

    # --- udo i noga z przodu -------------------------------------------------
    # Udo zlewa sie z tulowiem - osobna plama wygladala jak kieszen.
    # Wyjatki: sepie piora na udach (sulatnka) i puch jedwabistej.
    if b.get("vulture"):
        for i in range(7):
            base = TP((318 + i * 6, 410 + i * 3))
            tip = TP((350 + i * 9, 462 + i * 2))
            painted(svg, feather(base, tip, 8, bend=0.12), light(c_body, 0.1) if i % 2 else c_body,
                    ink=1.8, sdx=3, sdy=4, hatch=False, texture=False)
    elif b.get("fluffy"):
        painted(svg, cloud(T([(296, 398), (350, 396), (364, 436), (330, 456), (294, 440)]), 12, rnd=rnd),
                c_body, sdx=5, sdy=6, ink=2.2)
    else:
        fl = []
        for i in range(6):
            p = TP((306 + i * 9, 436 + (i % 2) * 4))
            fl.append("M%.1f %.1f q 3 8 8 9" % p)
        ink_line(svg, " ".join(fl), 1.8, shade(c_body, 0.55), 0.7)

    legs(svg, b, T, far=False)

    # --- kark: piora albo gola skora -----------------------------------------
    neck(svg, b, T, c_hackle)

    # --- glowa ---------------------------------------------------------------
    head(svg, b, T, c_comb)


def densify(points, n):
    """Rozklada n punktow rowno po obwodzie wielokata."""
    segs = []
    total = 0.0
    m = len(points)
    for i in range(m):
        a, c = points[i], points[(i + 1) % m]
        L = math.hypot(c[0] - a[0], c[1] - a[1])
        segs.append((a, c, L))
        total += L
    out = []
    step = total / n
    pos = 0.0
    i = 0
    acc = 0.0
    for k in range(n):
        target = k * step
        while acc + segs[i][2] < target and i < m - 1:
            acc += segs[i][2]
            i += 1
        a, c, L = segs[i]
        t = (target - acc) / L if L else 0
        out.append((a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t))
    return out


def cloud(points, n=34, bulge=0.62, rnd=None):
    """Brzeg jak obloczek: luki wypukle na zewnatrz miedzy punktami obwodu.
    Na puszysta jedwabista - poszarpany zygzak wygladal jak podarty papier."""
    pts = densify(points, n)
    # Kierunek obiegu: luk ma sie wybrzuszac na zewnatrz.
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    sweep = 1 if area > 0 else 0
    d = "M%.1f %.1f" % pts[0]
    for i in range(n):
        a, c = pts[i], pts[(i + 1) % n]
        r = math.hypot(c[0] - a[0], c[1] - a[1]) * bulge * (rnd.uniform(0.85, 1.15) if rnd else 1.0)
        d += " A%.1f %.1f 0 0 %d %.1f %.1f" % (r, r, sweep, c[0], c[1])
    return d + " Z"


def fluff_outline(points, rnd, amp):
    """Pierzasty, puszysty brzeg: duzo drobnych garbow wzdluz konturu."""
    out = []
    n = len(points)
    for i in range(n):
        a, c = points[i], points[(i + 1) % n]
        steps = 4
        for s in range(steps):
            t = s / float(steps)
            x = a[0] + (c[0] - a[0]) * t
            y = a[1] + (c[1] - a[1]) * t
            mx, my = 330, 360
            vx, vy = x - mx, y - my
            ln = math.hypot(vx, vy) or 1
            bump = amp * (1 if s % 2 else -0.35) * rnd.uniform(0.6, 1.2)
            out.append((x + vx / ln * bump, y + vy / ln * bump))
    return out


def pattern(svg, b, cid, T):
    kind = b.get("pattern")
    if not kind:
        # Delikatne luski pior, zeby tulow nie byl plaski.
        kind = "subtle"
    col = b.get("pattern_color", shade(b["body"], 0.5))
    out = []
    rnd = svg.rand
    for row in range(10):
        for colm in range(14):
            x = 200 + colm * 19 + (row % 2) * 9.5 + rnd.uniform(-2, 2)
            y = 280 + row * 17 + rnd.uniform(-2, 2)
            x, y = T([(x, y)])[0]
            if kind == "subtle":
                out.append('<path d="M%.1f %.1f q 9 11 18 0" stroke="%s" stroke-width="1.6" fill="none" '
                           'opacity="0.28"/>' % (x - 9, y, col))
            elif kind == "laced":
                out.append('<path d="M%.1f %.1f q 10 13 20 0" stroke="%s" stroke-width="3.2" fill="none" '
                           'opacity="0.85"/>' % (x - 10, y, col))
            elif kind == "spangled":
                out.append('<path d="M%.1f %.1f q 5 -3 10 0 q -1 9 -5 10 q -4 -1 -5 -10 Z" fill="%s" '
                           'opacity="0.9"/>' % (x - 5, y + 2, col))
            elif kind == "pencilled":
                out.append('<path d="M%.1f %.1f q 10 12 20 0 M%.1f %.1f q 6 7 12 0" stroke="%s" '
                           'stroke-width="2" fill="none" opacity="0.8"/>' % (x - 10, y, x - 6, y + 2, col))
            elif kind == "sheen":
                if rnd.random() < 0.35:
                    out.append('<path d="M%.1f %.1f q 9 9 18 0" stroke="%s" stroke-width="2.4" fill="none" '
                               'opacity="0.55"/>' % (x - 9, y, col))
    svg.add('<g clip-path="url(#%s)" filter="url(#wobble)">%s</g>' % (cid, "".join(out)))


def frizzle(svg, b, T, body_pts):
    """Kedzierzawe piora: rzedy pior wywinietych do gory i do przodu, od dolu
    do grzbietu, kazde z zawinietym koncem."""
    rnd = svg.rand
    col = b["body"]
    for row in range(6):
        y = 430 - row * 26
        for k in range(8 - abs(row - 2)):
            x = 236 + k * 26 + row * 6 + rnd.uniform(-5, 5)
            base = T([(x, y)])[0]
            ang = math.radians(-125 + rnd.uniform(-18, 18))
            L = rnd.uniform(26, 34)
            tip = (base[0] + math.cos(ang) * L, base[1] + math.sin(ang) * L)
            c = light(col, 0.12) if (row + k) % 2 else col
            painted(svg, feather(base, tip, 10, bend=0.18, tip_round=0.7), c, ink=2.0, sdx=3, sdy=4,
                    hatch=False, texture=False)
            ink_line(svg, "M%.1f %.1f a 6 6 0 1 0 %.1f %.1f" % (tip[0], tip[1], 9, 2), 2.0)


def tail(svg, b, T, color):
    kind = b.get("tail", "sickle")
    if kind == "none":
        return
    rnd = svg.rand
    sheen = b.get("tail_sheen")
    root = T([(430, 315)])[0]
    if kind == "fluffy":
        pts = T([(404, 302), (446, 248), (494, 258), (492, 322), (440, 344)])
        painted(svg, cloud(pts, 14, rnd=rnd), color)
        return
    if kind == "upright":
        for i in range(7):
            ang = math.radians(-100 + i * 9)
            L = 120 - abs(i - 3) * 8
            tip = (root[0] + math.cos(ang) * L - 10, root[1] + math.sin(ang) * L)
            painted(svg, sickle(root, tip, 9, 0.06), color if i % 2 else shade(color, 0.12),
                    ink=2.5, sdx=4, sdy=5, hatch=False, texture=False)
        return
    feathers = []
    if kind == "sickle":
        for i in range(7):
            ang = math.radians(-58 + i * 13)
            L = 120 - i * 4
            feathers.append((ang, L, 0.14 - i * 0.02, 10))
        # Dwa wielkie sierpy wygiete luk nad reszta - znak rozpoznawczy koguta.
        feathers.append((math.radians(-40), 175, 0.36, 12))
        feathers.append((math.radians(-25), 165, 0.40, 11))
    elif kind == "long":
        for i in range(9):
            ang = math.radians(-35 + i * 9)
            L = 260 + rnd.uniform(-20, 30)
            feathers.append((ang, L, 0.25, 9))
    elif kind == "very_long":
        # Onagadori: ogon splywa luk w dol i ciagnie sie po ziemi poza obraz.
        for i in range(12):
            ang = math.radians(22 + i * 3.5)
            L = 420 + rnd.uniform(-30, 70)
            feathers.append((ang, L, -0.2 - i * 0.012, 8))
    # Od tylu do przodu: dalsze piora ciemniejsze.
    for i, (ang, L, curl, w) in enumerate(reversed(feathers)):
        tip = (root[0] + math.cos(ang) * L, root[1] + math.sin(ang) * L)
        c = shade(color, 0.22) if i < len(feathers) // 2 else color
        painted(svg, sickle(root, tip, w, curl), c, ink=2.6, sdx=4, sdy=6, hatch=False, texture=False)
        if sheen:
            d = sickle(root, tip, w * 0.35, curl)
            svg.add('<path d="%s" fill="%s" opacity="0.55" transform="translate(-2 -3)"/>' % (d, sheen))


def legs(svg, b, T, far):
    c = b.get("leg", "#E8B84A")
    if far:
        c = shade(c, 0.3)
    thick = b.get("leg_w", 12.0)
    x0 = 352 if far else 318
    top = T([(x0, 440)])[0]
    ground_y = 505
    knee = (top[0] - 4, top[1] + (ground_y - top[1]) * 0.5)
    foot = (top[0] - 8, ground_y)
    d = "M%.1f %.1f L%.1f %.1f L%.1f %.1f" % (top + knee + foot)
    if b.get("scaly"):
        # Dong Tao: noga jak pien - gruba, guzowata, w czerwonych luskach,
        # u dolu szersza niz u gory.
        w0, w1 = thick * 0.55, thick * 0.8
        leg = [(top[0] - w0, top[1]), (top[0] + w0, top[1]), (knee[0] + w0 * 1.1, knee[1]),
               (foot[0] + w1, foot[1] - 4), (foot[0] - w1, foot[1] - 4), (knee[0] - w0 * 1.1, knee[1])]
        lid = painted(svg, cloud(leg, 16, bulge=0.75, rnd=svg.rand), c, ink=3.2, sdx=5, sdy=4, hatch=True)
        scales = []
        for row in range(9):
            y = top[1] + 6 + row * (foot[1] - top[1] - 10) / 9.0
            for k in range(3):
                x = foot[0] - w1 + 6 + k * (w1 * 0.66) + (row % 2) * 5
                scales.append('<path d="M%.1f %.1f q 5 6 10 0" stroke="%s" stroke-width="2.2" fill="none" '
                              'opacity="0.8"/>' % (x, y, shade(c, 0.5)))
        svg.add('<g clip-path="url(#%s)" filter="url(#wobble)">%s</g>' % (lid, "".join(scales)))
    else:
        ink_line(svg, d, thick + 5)
        svg.add('<path d="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="round"/>'
                % (d, c, thick))
    # Palce: trzy do przodu (w lewo) i jeden do tylu. Piec u ras z dodatkowym palcem.
    toes = [(-38, 4), (-30, 10), (-22, 14), (16, 2)]
    if b.get("five_toes"):
        toes.append((10, 8))
    for tx, ty in toes:
        dt = "M%.1f %.1f q %.1f %.1f %.1f %.1f" % (foot[0], foot[1], tx * 0.5, ty * 0.3 + 2, tx, ty)
        ink_line(svg, dt, thick * 0.55 + 4)
        svg.add('<path d="%s" stroke="%s" stroke-width="%.1f" fill="none" stroke-linecap="round"/>'
                % (dt, c, thick * 0.55))
    if b.get("leg_feathers"):
        fc = b.get("leg_feather_color", b["body"])
        if far:
            fc = shade(fc, 0.25)
        heavy = b.get("leg_feathers") == "heavy"
        if heavy:
            # Pierzasty "kozak" od kolana po palce, z fredzlami na zewnatrz.
            boot = [(knee[0] - 12, knee[1] - 22), (knee[0] + 14, knee[1] - 24), (knee[0] + 26, foot[1] - 14),
                    (foot[0] + 20, foot[1] + 6), (foot[0] - 30, foot[1] + 8), (foot[0] - 12, foot[1] - 16)]
            painted(svg, cloud(boot, 13, bulge=0.7, rnd=svg.rand), fc, ink=2.4, sdx=4, sdy=6, hatch=False)
            for i in range(4):
                base = (foot[0] + 8 + i * 3, knee[1] + i * 14)
                tip = (base[0] + 22, base[1] + 16)
                painted(svg, feather(base, tip, 6, bend=0.12, tip_round=0.4), light(fc, 0.08), ink=1.8,
                        sdx=2, sdy=3, hatch=False, texture=False)
        else:
            for i in range(4):
                base = (knee[0] + 4, knee[1] - 10 + i * 16)
                tip = (base[0] + 16, base[1] + 14)
                painted(svg, feather(base, tip, 4.5, bend=0.12, tip_round=0.4), fc, ink=1.6, sdx=2, sdy=2,
                        hatch=False, texture=False)


def neck(svg, b, T, color):
    rnd = svg.rand
    if b.get("naked_neck"):
        skin = b.get("neck_skin", "#D9584C")
        nd = catmull(T([(196, 214), (222, 196), (248, 228), (262, 282), (232, 300), (210, 270)]))
        painted(svg, nd, skin, sdx=6, sdy=8)
        # Muszka z pior u nasady szyi.
        for i in range(8):
            base = T([(222 + i * 6, 288 + i * 2)])[0]
            tip = T([(214 + i * 7, 312 + rnd.uniform(-3, 6))])[0]
            painted(svg, feather(base, tip, 6, bend=0.1), color, ink=1.8, sdx=3, sdy=3, hatch=False,
                    texture=False)
        return
    if b.get("fluffy"):
        nd = T([(188, 214), (222, 168), (262, 206), (292, 280), (250, 322), (206, 300)])
        painted(svg, cloud(nd, 16, rnd=rnd), color)
        return
    # Najpierw pelna szyja od glowy do piersi, na nia peleryna z dlugich,
    # spiczastych pior splywajacych z karku na barki i piers.
    base = T([(186, 206), (210, 168), (240, 186), (266, 230), (304, 286), (262, 322), (220, 322), (200, 270)])
    painted(svg, catmull(base), color, sdx=6, sdy=7)
    stripe = b.get("hackle_stripe")
    count = 15
    for i in range(count):
        t = i / float(count - 1)
        root = T([(216 + t * 36, 182 + t * 24)])[0]
        tip = T([(226 + t * 140 + rnd.uniform(-5, 5), 292 + t * 8 + rnd.uniform(-5, 5))])[0]
        c = color if i % 3 else light(color, 0.18)
        if i % 4 == 1:
            c = shade(color, 0.12)
        painted(svg, feather(root, tip, 12.5, bend=-0.08 + t * 0.1), c, ink=1.8, sdx=4, sdy=5, hatch=False,
                texture=False)
        if stripe:
            svg.add('<path d="%s" fill="%s" opacity="0.9"/>' % (feather(root, tip, 3.0, bend=-0.08 + t * 0.1),
                                                              stripe))


def head(svg, b, T, comb_color):
    rnd = svg.rand
    hx, hy = T([(205, 180)])[0]
    hs = b.get("head_scale", 1.18)
    svg.add('<g transform="translate(%.1f %.1f) scale(%.2f) translate(%.1f %.1f)">' % (hx, hy, hs, -hx, -hy))
    face = b.get("face", "#D8322C")
    c_head = b.get("head", b.get("hackle", b["body"]))
    eye_col = b.get("eye", "#E8932C")
    beak = b.get("beak", "#E3BC62")
    # Grzebien (za glowa, wiec najpierw).
    comb = b.get("comb", "single")
    cs = b.get("comb_size", 1.0)
    if comb == "single":
        pts = [(hx - 30, hy - 14)]
        n = 5
        for i in range(n):
            x = hx - 26 + i * 13 * cs
            pts.append((x - 4, hy - 30 - (16 + 10 * math.sin(i / (n - 1) * math.pi)) * cs))
            pts.append((x + 4, hy - 26 - 2 * cs))
        pts.append((hx + 36 * cs, hy - 20 * cs))
        pts.append((hx + 20, hy - 10))
        painted(svg, catmull(pts, tension=0.25), comb_color, sdx=4, sdy=6, hatch=False)
    elif comb == "rose":
        pts = [(hx - 26, hy - 18), (hx - 10, hy - 34), (hx + 16, hy - 32), (hx + 44, hy - 30),
               (hx + 18, hy - 20), (hx - 6, hy - 16)]
        painted(svg, catmull(pts), comb_color, sdx=3, sdy=4, hatch=False)
        for i in range(5):
            svg.add('<circle cx="%.1f" cy="%.1f" r="2.2" fill="%s"/>' % (hx - 10 + i * 9, hy - 27, shade(comb_color, 0.4)))
    elif comb in ("pea", "walnut"):
        pts = [(hx - 24, hy - 18), (hx - 14, hy - 32), (hx + 6, hy - 34), (hx + 14, hy - 22), (hx - 4, hy - 16)]
        painted(svg, catmull(pts), comb_color, sdx=3, sdy=4, hatch=False)
        ink_line(svg, "M%.1f %.1f Q %.1f %.1f %.1f %.1f" % (hx - 16, hy - 24, hx - 4, hy - 30, hx + 8, hy - 24),
                 1.6, shade(comb_color, 0.5))
    elif comb == "v":
        for side in (-1, 1):
            pts = [(hx - 18, hy - 22), (hx - 24 + side * 6, hy - 44), (hx - 10, hy - 26)]
            painted(svg, catmull(pts, tension=0.3), comb_color, sdx=2, sdy=3, hatch=False)
    # Glowa.
    hd = [(hx - 30, hy - 6), (hx - 18, hy - 28), (hx + 8, hy - 32), (hx + 30, hy - 14), (hx + 30, hy + 16),
          (hx + 6, hy + 30), (hx - 22, hy + 22)]
    painted(svg, cloud(hd, 14, rnd=rnd) if b.get("fluffy") else catmull(hd), c_head, sdx=5, sdy=7)
    # Twarz (czerwona skora wokol oka).
    fd = catmull([(hx - 26, hy - 6), (hx - 12, hy - 18), (hx + 8, hy - 12), (hx + 10, hy + 10),
                  (hx - 8, hy + 18), (hx - 24, hy + 10)])
    if not b.get("hide_face"):
        painted(svg, fd, face, ink=0, sdx=3, sdy=4, hatch=False)
    # Korale.
    w = b.get("wattle", 1.0)
    if w > 0:
        for dx, sc in ((-4, 1.0), (8, 0.85)):
            wp = [(hx - 22 + dx, hy + 14), (hx - 8 + dx, hy + 14), (hx - 6 + dx, hy + 14 + 24 * w * sc),
                  (hx - 16 + dx, hy + 22 + 22 * w * sc), (hx - 24 + dx, hy + 26)]
            painted(svg, catmull(wp), shade(b.get("wattle_color", comb_color), 0.08 if dx else 0),
                    sdx=3, sdy=5, hatch=False)
    # Zausznica.
    lobe = b.get("earlobe", face)
    painted(svg, catmull([(hx + 6, hy + 2), (hx + 18, hy + 0), (hx + 20, hy + 14), (hx + 8, hy + 16)]), lobe,
            ink=2.2, sdx=2, sdy=3, hatch=False)
    # Dziob.
    bd = "M%.1f %.1f Q %.1f %.1f %.1f %.1f Q %.1f %.1f %.1f %.1f Z" % (
        hx - 26, hy - 10, hx - 46, hy - 6, hx - 52, hy + 8, hx - 40, hy + 6, hx - 24, hy + 6)
    painted(svg, bd, beak, ink=2.8, sdx=2, sdy=3, hatch=False)
    ink_line(svg, "M%.1f %.1f L%.1f %.1f" % (hx - 26, hy, hx - 44, hy + 2), 1.6)
    svg.add('<circle cx="%.1f" cy="%.1f" r="2" fill="%s"/>' % (hx - 30, hy - 4, INK))
    # Oko.
    ex, ey = hx - 8, hy - 4
    svg.add('<circle cx="%.1f" cy="%.1f" r="7.5" fill="%s" stroke="%s" stroke-width="2.4"/>' % (ex, ey, eye_col, INK))
    svg.add('<circle cx="%.1f" cy="%.1f" r="3.6" fill="%s"/>' % (ex - 1, ey, INK))
    svg.add('<circle cx="%.1f" cy="%.1f" r="1.8" fill="#FFFFFF"/>' % (ex - 2.5, ey - 2.5))
    ink_line(svg, "M%.1f %.1f Q %.1f %.1f %.1f %.1f" % (ex - 9, ey - 8, ex, ey - 12, ex + 9, ey - 7), 2.6)
    # Czub, broda, baki.
    crest = b.get("crest")
    cc = b.get("crest_color", c_head)
    if crest:
        sizes = {"polish": (50, 40), "silkie": (40, 26), "sultan": (36, 24), "pavlov": (40, 16)}
        R, n = sizes.get(crest, (30, 16))
        cxh, cyh = hx + 4, hy - 30
        if crest in ("polish", "silkie"):
            # Najpierw gesta kula pod spodem, zeby miedzy piorami nie przeswitywalo niebo.
            painted(svg, cloud([(cxh - R * 0.8, cyh), (cxh, cyh - R * 0.85), (cxh + R * 0.8, cyh),
                                (cxh, cyh + R * 0.35)], 12, rnd=rnd), cc, ink=2.0, sdx=3, sdy=4, hatch=False)
        for i in range(n):
            if crest == "pavlov":
                ang = math.radians(-150 + i * (120.0 / (n - 1)))
            elif crest == "polish":
                ang = math.radians(-215 + rnd.uniform(0, 250))
            else:
                ang = math.radians(-200 + i * (220.0 / (n - 1)))
            L = R * rnd.uniform(0.8, 1.15)
            tip = (cxh + math.cos(ang) * L, cyh + math.sin(ang) * L * (1.3 if crest == "pavlov" else 0.9))
            base = (cxh + math.cos(ang) * 4, cyh + 6)
            col = cc if i % 2 else light(cc, 0.15)
            if crest == "silkie":
                painted(svg, feather(base, tip, 10, bend=0.2, tip_round=0.9), col, ink=1.8, sdx=2, sdy=3,
                        hatch=False, texture=False)
            else:
                painted(svg, feather(base, tip, 7 if crest != "polish" else 9, bend=0.12), col, ink=2.0,
                        sdx=2, sdy=3, hatch=False, texture=False)
    if b.get("beard"):
        bc = b.get("beard_color", c_head)
        for i in range(9):
            base = (hx - 20 + i * 4, hy + 10)
            tip = (hx - 26 + i * 6 + rnd.uniform(-3, 3), hy + 40 + rnd.uniform(-4, 6))
            painted(svg, feather(base, tip, 6, bend=0.05, tip_round=0.5), bc if i % 2 else light(bc, 0.15),
                    ink=1.8, sdx=2, sdy=3, hatch=False, texture=False)
        for i in range(5):
            base = (hx + 10, hy + 2 + i * 3)
            tip = (hx + 30 + rnd.uniform(-3, 3), hy + 4 + i * 6)
            painted(svg, feather(base, tip, 6, bend=-0.1, tip_round=0.6), bc, ink=1.8, sdx=2, sdy=3,
                    hatch=False, texture=False)
    if b.get("ear_tufts"):
        tc = b.get("tuft_color", c_head)
        for i in range(7):
            base = (hx + 10, hy + 6)
            tip = (hx + 46 + i * 3, hy + 2 + i * 9)
            painted(svg, feather(base, tip, 6, bend=-0.3), tc if i % 2 else shade(tc, 0.15), ink=1.8,
                    sdx=2, sdy=2, hatch=False, texture=False)
    svg.add('</g>')


# ---------------------------------------------------------------------------
# rasy
# ---------------------------------------------------------------------------

BREEDS = {
    "leghorn": dict(
        body="#F8F5EC", hackle="#FFFDF4", wing="#F1ECDF", tail_color="#F4F0E4", comb="single", comb_size=1.25,
        earlobe="#FAF6EE", leg="#EFC34A", wattle=1.3, pattern_color="#B8AE9E",
        bg=dict(sky=("#F6C7A8", "#FCE8CF"), hills=("#B9B48A", "#97A774", "#7E955E"), ground="#9BB86F",
                landmark="cypress", lm_color="#556B48", sun_pos=(420, 170))),
    "rhode": dict(
        body="#A23E1E", hackle="#B8542A", wing="#8A3218", tail_color="#22302E", tail_sheen="#4E8A72",
        comb="single", leg="#E9B847", pattern_color="#5E1E0E",
        bg=dict(sky=("#B8D3E6", "#EAF1E8"), hills=("#A9BFA0", "#8FAF7E", "#7C9E68"), ground="#94B66C",
                landmark="barn", lm_color="#B04A3A", sun_pos=(140, 140))),
    "szabo": dict(
        body="#F6E7CC", hackle="#FBF0DA", wing="#F1DFC0", tail_color="#EAD6B0", comb="single", frizzle=True,
        leg="#EFC34A", pattern_color="#B49D78",
        bg=dict(sky=("#D7C6E8", "#F6E6EE"), hills=("#BFB0D0", "#A99DBE", "#9AA987"), ground="#A9BE80",
                landmark="garden", lm_color="#9C8DB4", sun_pos=(460, 150))),
    "nagoszyja": dict(
        body="#E3A26C", hackle="#E9AE78", wing="#C98852", tail_color="#3A2E28", tail_sheen="#6F8F6A",
        comb="single", naked_neck=True, neck_skin="#D8574A", leg="#EBC04E", pattern_color="#9B5E30",
        bg=dict(sky=("#C9B8D8", "#F2DCCB"), hills=("#9C93AE", "#8E9C82", "#7E9468"), ground="#8EAE68",
                landmark="castle", lm_color="#6A607E", sun_pos=(150, 160), peaks=70)),
    "marans": dict(
        body="#2E2826", hackle="#C8783A", head="#C27234", wing="#2A2523", breast="#2A2423",
        tail_color="#1E2422", tail_sheen="#3E7F6A", comb="single", leg="#E8DCC8", leg_feathers="light",
        leg_feather_color="#2E2826", pattern="sheen", pattern_color="#4E7F70", eye="#D8822A", wing_bar="#A85A28",
        bg=dict(sky=("#A8C6DA", "#F0E3CF"), hills=("#A7B4BC", "#93A8A0"), ground="#9DB67A", landmark="boats",
                lm_color="#7A5A4A", sea="#8DB7CB", sun_pos=(470, 150))),
    "araukana": dict(
        body="#93A9BE", hackle="#A9BDD0", wing="#7F97AE", tail="none", comb="pea", wattle=0.2,
        ear_tufts=True, tuft_color="#4E6884", leg="#9AA89A", pattern="laced", pattern_color="#5F7690",
        bg=dict(sky=("#B9D2EA", "#F3E7DA"), hills=("#B6B4CE", "#9FA4C2", "#8FA27E"), ground="#9AB474",
                landmark="andes", snow=True, peaks=140, sun_pos=(140, 130))),
    "jedwabista": dict(
        body="#FBF8F2", hackle="#FFFFFF", wing="#F3EEE4", tail="fluffy", tail_color="#F6F1E8", fluffy=True,
        comb="walnut", comb_color="#5A2A3E", face="#6A4458", wattle=0.25, wattle_color="#5A2A3E",
        earlobe="#46B3C9", crest="silkie", crest_color="#FFFFFF", beard=True, beard_color="#F7F2EA",
        leg="#5A6070", leg_feathers="heavy", leg_feather_color="#F6F1E8", five_toes=True, beak="#6A6E7A",
        eye="#2A2230", saddle=False, pattern_color="#CFC6B8",
        bg=dict(sky=("#DCD6EE", "#F8EEE4"), hills=("#C9C6DE", "#B6B9D2", "#A3B49A"), ground="#A9BF8A",
                landmark="misty", lm_color="#A9A6C6", sun_pos=(450, 150), peaks=90)),
    "serama": dict(
        body="#E9B45E", hackle="#F2C474", wing="#D39A44", breast="#C7843A", tail="upright",
        tail_color="#2C2A28", tail_sheen="#5E8A6A", comb="single", comb_size=0.9, leg="#EBC04E",
        pose=dict(sx=0.82, sy=0.9, rot=-18, dy=10), pattern_color="#9A6A2A",
        bg=dict(sky=("#9FD3D0", "#F7E4C4"), hills=("#86BFA8", "#76AE86"), ground="#93BC6A", landmark="palms",
                lm_color="#3E6E54", sun_pos=(150, 150))),
    "brahma": dict(
        body="#F5EEDF", hackle="#FAF4E6", hackle_stripe="#2E2C36", wing="#EDE3CF", tail_color="#2C2B33",
        tail_sheen="#59607A", comb="pea", comb_size=0.8, wattle=0.5, leg="#EFCB66", leg_feathers="heavy",
        leg_feather_color="#F1E9DA", pose=dict(sx=1.12, sy=1.08, dy=-8), pattern_color="#BCAF98",
        wing_bar="#3A3842",
        bg=dict(sky=("#C2CFE0", "#F1E6DA"), hills=("#AAB7BF", "#98AB92", "#86A07A"), ground="#93B072",
                landmark="garden", lm_color="#7F9C7A", sun_pos=(450, 160))),
    "czubatka": dict(
        body="#3E3B48", hackle="#4C4858", wing="#3A3744", tail_color="#2C2A33", tail_sheen="#7C7898",
        comb="v", crest="polish", crest_color="#F4F1F7", beard=False, leg="#7C8290", pattern="laced",
        pattern_color="#D9D3E6", wattle=0.3,
        bg=dict(sky=("#BFD4E6", "#F3EAD8"), hills=("#A9B8C2", "#93AA8C"), ground="#97B477", landmark="windmill",
                lm_color="#8A7A6E", sun_pos=(150, 150), peaks=20)),
    "pavlovskaya": dict(
        body="#D8AE62", hackle="#E3BC72", wing="#C69A4E", tail_color="#2E2A2E", tail_sheen="#6A6A80",
        comb="v", crest="pavlov", crest_color="#D9AE62", beard=True, beard_color="#E0B86C", leg="#6C6670",
        leg_feathers="heavy", leg_feather_color="#CFA45A", pattern="spangled", pattern_color="#2E2630",
        wattle=0.2,
        bg=dict(sky=("#CCD9EA", "#F4ECE6"), hills=("#E9EEF4", "#D9E2EC", "#C9D6E2"), ground="#E3E9F0",
                landmark="church", lm_color="#8A7C9A", sun_pos=(140, 150), snow=True)),
    "feniks": dict(
        body="#2E2A26", hackle="#E8B063", head="#E3A858", wing="#C88E46", breast="#2A2622", tail="long",
        tail_color="#24282A", tail_sheen="#4E8A78", comb="single", leg="#7C8086", saddle_color="#E2A858",
        saddle_len=40, pattern="sheen", pattern_color="#4F7E70",
        bg=dict(sky=("#C8D8C6", "#F3E8D2"), hills=("#A6B89E", "#8EA486"), ground="#8FAE6E", landmark="forest",
                lm_color="#5E7A5E", sun_pos=(150, 140))),
    "deathlayer": dict(
        body="#F2F0EC", hackle="#FBFAF6", wing="#E8E6E0", tail_color="#2E3036", tail_sheen="#7A8090",
        comb="rose", earlobe="#F5F3EE", leg="#7C8796", pattern="pencilled", pattern_color="#5A6270",
        bg=dict(sky=("#BFD0DC", "#F2EBDD"), hills=("#A9B8AE", "#93AA88"), ground="#94B270", landmark="timber",
                lm_color="#6A5444", sun_pos=(450, 150))),
    "sultanka": dict(
        body="#FBF9F4", hackle="#FFFFFF", wing="#F2EEE6", tail_color="#F5F1E8", comb="v", crest="sultan",
        crest_color="#FFFFFF", beard=True, beard_color="#F8F5EE", leg="#9AA0AC", leg_feathers="heavy",
        leg_feather_color="#F4F0E8", vulture=True, five_toes=True, wattle=0.2, pattern_color="#CFC8BA",
        bg=dict(sky=("#F1C9B6", "#F8E9D6"), hills=("#C7B0C2", "#AFA2B8"), ground="#A9B888", landmark="domes",
                lm_color="#9A86A6", sun_pos=(150, 160))),
    "onagadori": dict(
        body="#F3E6C8", hackle="#FBF1DC", head="#F6EAD0", wing="#E9D7AE", tail="very_long",
        tail_color="#F7EED8", saddle_color="#F6EBD2", saddle_len=70, comb="single", leg="#E7C25A",
        pattern_color="#BFA77A", shadow_x=380,
        bg=dict(sky=("#E9C8D2", "#F8EAD8"), hills=("#C9B6C8", "#B2A9C2", "#9DAE8A"), ground="#A7BC84",
                landmark="torii", lm_color="#C65A48", sun_pos=(140, 150), peaks=80)),
    "dongtao": dict(
        body="#9E4529", hackle="#C08A58", wing="#7E3A22", breast="#3A2A24", tail_color="#2A2C2A",
        tail_sheen="#4E7A62", comb="pea", comb_size=0.9, wattle=0.35, leg="#D86A4A", leg_w=26.0, scaly=True,
        pose=dict(sx=1.1, sy=1.05, dy=-14), pattern_color="#5A2414", face="#D04A38",
        bg=dict(sky=("#C6DDBE", "#F4E6C6"), hills=("#A8C49A", "#93B67E"), ground="#9DBB6A", landmark="terraces",
                lm_color="#7FA66A", sun_pos=(450, 150))),
    "cemani": dict(
        body="#24222B", hackle="#2C2A35", head="#26242E", wing="#22202A", tail_color="#1C1B22",
        tail_sheen="#4F8F86", comb="single", comb_color="#2A2632", face="#2E2A36", wattle_color="#2A2632",
        earlobe="#34303E", leg="#2B2A32", beak="#2A2830", eye="#1A1820", pattern="sheen",
        pattern_color="#5A5F8E",
        bg=dict(sky=("#B7A8D6", "#F0D6DA"), hills=("#9E90BE", "#8C86AE", "#7C8C8A"), ground="#8EA27A",
                landmark="volcano", lm_color="#7A6A9A", sun_pos=(460, 140))),
}


def build_svg(breed_id):
    b = BREEDS[breed_id]
    svg = Svg(seed=sum(ord(c) for c in breed_id))
    background(svg, b)
    bird(svg, b)
    return svg.render(b.get("frame", (110, 70, 480)))


def finish(png_path, out_path):
    """Ziarno papieru, winieta i cieplejszy, pastelowy kolor."""
    im = Image.open(png_path).convert("RGB").crop((8, 8, SIZE + 8, SIZE + 8))
    arr = np.asarray(im).astype(np.float32) / 255.0
    h, w, _ = arr.shape
    rng = np.random.default_rng(42)
    grain = rng.normal(0.0, 0.025, (h, w, 1)).astype(np.float32)
    arr = np.clip(arr + grain, 0, 1)
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    vig = np.clip(1.0 - 0.22 * np.clip(r - 0.55, 0, 1) ** 1.5, 0, 1)[..., None]
    arr = arr * vig + (1 - vig) * np.array([0.32, 0.24, 0.30], dtype=np.float32)
    # Pastel: odrobina mleka w cieniach.
    arr = arr * 0.94 + 0.05
    im = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
    im = ImageEnhance.Color(im).enhance(1.08)
    im = im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    im.save(out_path, "WEBP", quality=88, method=6)


def main(ids):
    os.makedirs(OUT_DIR, exist_ok=True)
    for breed_id in ids or sorted(BREEDS):
        svg_text = build_svg(breed_id)
        with tempfile.TemporaryDirectory() as tmp:
            svg_path = os.path.join(tmp, breed_id + ".svg")
            png_path = os.path.join(tmp, breed_id + ".png")
            with open(svg_path, "w") as f:
                f.write(svg_text)
            # O 16 px wiecej i przyciecie: filtr przesuniecia zostawia przy
            # samej krawedzi jasna nitke (ciagnie piksele spoza obrazka).
            subprocess.run(["rsvg-convert", "-w", str(SIZE + 16), "-h", str(SIZE + 16), svg_path,
                            "-o", png_path], check=True)
            out = os.path.join(OUT_DIR, breed_id + ".webp")
            finish(png_path, out)
            if os.environ.get("KEEP_SVG"):
                with open(os.path.join("/tmp", breed_id + "_portrait.svg"), "w") as f:
                    f.write(svg_text)
        print("portret:", breed_id)


if __name__ == "__main__":
    main(sys.argv[1:])
