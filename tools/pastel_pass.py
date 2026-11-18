#!/usr/bin/env python3
"""Jednorazowe przestrojenie palety na pastelowa (grafika 2.1).

Przelicza kazdy kolor w plikach SVG i w generatorze tla:
  - delikatnie rozjasnia wypelnienia, zostawiajac nasycenie (ma byc pastelowo,
    ale nadal kolorowo — mocniejsze zmiekczenie dalo wyblakly, chorowity obraz),
  - zamienia ciemne, twarde kontury na jeden mieki, cieply odcien,
  - scienia linie konturu.

Skrypt zapisuje wynik do zrodel na stale — w repo zostaja juz pastelowe
wartosci. Uruchamia sie go raz; nie jest czescia budowania gry.
"""
import colorsys
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOFT_OUTLINE = "#8A6A55"
# Kontury, ktore byly prawie czarne — wszystkie ida na jeden mieki odcien.
HARD_OUTLINES = {"#4a2d16", "#5a3720", "#4b2e16", "#8a5a2b", "#7a4a22", "#7a4a20", "#8e2e20", "#b9830d"}

FILES = [
    *sorted((ROOT / "assets/sprites/buildings").glob("*.svg")),
    *sorted((ROOT / "assets/sprites/world").glob("*.svg")),
    *sorted((ROOT / "assets/ui").glob("*.svg")),
    ROOT / "assets/icon.svg",
    ROOT / "tools/gen_ground.py",
]

HEX = re.compile(r"#([0-9a-fA-F]{6})\b")
STROKE_WIDTH = re.compile(r'stroke-width="([\d.]+)"')


def pastel(hex_value: str) -> str:
    r, g, b = (int(hex_value[i:i + 2], 16) / 255 for i in (0, 2, 4))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    s *= 0.92
    l += (0.90 - l) * 0.20
    r, g, b = colorsys.hls_to_rgb(h, min(l, 0.97), s)
    return "#%02X%02X%02X" % tuple(round(c * 255) for c in (r, g, b))


def convert(text: str) -> str:
    def repl(match: re.Match) -> str:
        value = match.group(1).lower()
        if value in HARD_OUTLINES:
            return SOFT_OUTLINE
        return pastel(value)

    text = HEX.sub(repl, text)
    # Cienszy kontur: 5 -> 4, 6 -> 4.8 itd., ale nie cienszy niz 2.
    text = STROKE_WIDTH.sub(lambda m: 'stroke-width="%g"' % max(2.5, round(float(m.group(1)) * 0.85, 1)), text)
    return text


if __name__ == "__main__":
    for path in FILES:
        if not path.exists():
            continue
        original = path.read_text()
        path.write_text(convert(original))
        print("przestrojone:", path.relative_to(ROOT))
