#!/usr/bin/env python3
"""Generuje grafike koguta dla kazdej rasy z data/breeds.json.

Kogutow jest tyle, ile ras (siedemnascie), a rysowanie kazdego z reki nie
mialoby sensu: rasy roznia sie przede wszystkim upierzeniem. Szablon jest
jeden — sylwetka z wysoko trzymana glowa, duzym grzebieniem i siepem
(sierpowym ogonem) — a podmieniaja sie w nim kolory piora.

Plotno 170x130, stopy na wysokosci y=118: dokladnie tak samo jak w grafikach
kur, zeby Sprite2D w farm_chicken.tscn (offset 4,-53) stawial koguta nogami
na punkcie (0,0) wezla. Bez tego kogut unosilby sie nad wybiegiem.

Uruchomienie:  python3 tools/gen_roosters.py
"""

import json
import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sprites" / "animals"

# Dla kazdej rasy: (jasne piero, bazowe, ciemne, ogon, grzebien).
# Kolory ida za prawdziwym upierzeniem rasy, zeby kogut byl rozpoznawalny
# obok swoich kur.
PALETTE = {
	"leghorn":     ("#FFFFFF", "#F0F0F0", "#D2D2D2", "#E4E4E4", "#E0463F"),
	"rhode":       ("#C06636", "#9A4A24", "#6E3316", "#4A2410", "#D6453E"),
	"szabo":       ("#F4E7D2", "#E2D0B2", "#C0A684", "#D6C0A0", "#DF5048"),
	"nagoszyja":   ("#DC8056", "#C2553A", "#8E3722", "#6B2817", "#E4584C"),
	"marans":      ("#4A4752", "#2B2B33", "#17171D", "#8B5A3C", "#D9453F"),
	"araukana":    ("#A9BFD1", "#7B96AE", "#566E82", "#445666", "#E4706A"),
	"jedwabista":  ("#FBF7F0", "#F0E9DC", "#D8CDBA", "#E6DCCA", "#5E7FA8"),
	"serama":      ("#E0A855", "#C8863C", "#9A6224", "#6E4414", "#DD4A44"),
	"brahma":      ("#FBF2E0", "#EFE2C8", "#CFC0A2", "#2E2C36", "#DA4A44"),
	"czubatka":    ("#4C4C58", "#33333D", "#1C1C24", "#F2EEE4", "#D8453F"),
	"pavlovskaya": ("#E2C277", "#C9A24B", "#9A7828", "#3A3038", "#DA4A44"),
	"feniks":      ("#D79C50", "#B4772C", "#845216", "#2E2822", "#DB4740"),
	"deathlayer":  ("#E8E8DE", "#CFCFC2", "#A8A89A", "#2A2A30", "#D6423C"),
	"sultanka":    ("#FFFBF2", "#F7F3EA", "#DCD6C6", "#EFE8D8", "#D8453F"),
	"onagadori":   ("#F8F0DE", "#F0E6D2", "#D2C6AC", "#3A3228", "#D9453E"),
	"dongtao":     ("#CE7850", "#B35A35", "#82391C", "#5A2612", "#DD4C44"),
	"cemani":      ("#34343E", "#1B1B22", "#0C0C10", "#101016", "#2A2A32"),
}

TEMPLATE = """<svg xmlns="http://www.w3.org/2000/svg" width="170" height="130" viewBox="0 0 170 130">
  <!-- Kogut rasy {breed}. Plik generowany przez tools/gen_roosters.py -
       recznych poprawek nie wprowadzac, bo zginą przy nastepnym przebiegu. -->
  <defs>
    <radialGradient id="b{slug}" cx="62" cy="62" r="60" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{light}"/>
      <stop offset="0.55" stop-color="{base}"/>
      <stop offset="1" stop-color="{dark}"/>
    </radialGradient>
    <radialGradient id="h{slug}" cx="108" cy="34" r="30" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{light}"/>
      <stop offset="1" stop-color="{base}"/>
    </radialGradient>
    <linearGradient id="k{slug}" x1="130" y1="40" x2="152" y2="52" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFD98A"/>
      <stop offset="1" stop-color="#EDA845"/>
    </linearGradient>
  </defs>

  <g stroke="#8A6A55" stroke-width="4" stroke-linejoin="round" stroke-linecap="round">
    <ellipse cx="78" cy="122" rx="40" ry="8" fill="#6B8F4E" fill-opacity="0.28" stroke="none"/>

    <!-- siep: dlugie piora ogona wygiete w luk wysoko nad grzbietem.
         To one odrozniaja koguta od kury na pierwszy rzut oka. -->
    <path d="M48 62Q18 34 30 4Q38 32 56 48Z" fill="{tail}"/>
    <path d="M44 68Q6 44 6 12Q24 42 50 56Z" fill="{dark}"/>
    <path d="M42 76Q2 62 2 34Q22 58 46 66Z" fill="{tail}"/>
    <path d="M44 84Q8 88 8 62Q28 74 48 70Z" fill="{dark}"/>

    <!-- nogi: kogut stoi wyzej od kury -->
    <path d="M70 102v16M70 118h-10M70 118h10" stroke="#EDA845"/>
    <path d="M94 102v16M94 118h-10M94 118h10" stroke="#EDA845"/>

    <!-- tulow -->
    <ellipse cx="76" cy="74" rx="40" ry="33" fill="url(#b{slug})"/>

    <!-- skrzydlo -->
    <path d="M58 66Q82 56 96 76Q78 92 60 85Q52 75 58 66Z" fill="{light}" fill-opacity="0.75"/>
    <path d="M64 73Q76 69 86 77" fill="none" stroke-width="3"/>

    <!-- szyja i glowa wysoko nad tulowiem -->
    <path d="M96 62Q100 42 108 36" fill="none" stroke-width="12" stroke="{base}"/>
    <circle cx="112" cy="34" r="22" fill="url(#h{slug})"/>

    <!-- duzy, zebaty grzebien -->
    <path d="M98 16q5-13 11-4q5-14 11-3q5-12 10-1q4-9 7 3" fill="{comb}"/>
    <!-- korale pod dziobem -->
    <path d="M124 50q-5 14-14 10q-2-11 6-15Z" fill="{comb}"/>
    <path d="M134 48q6 10 0 14q-6-3-5-11Z" fill="{comb}"/>

    <!-- dziob -->
    <path d="M132 36l17 6-17 6Z" fill="url(#k{slug})"/>

    <!-- oko -->
    <circle cx="122" cy="30" r="4.5" fill="#3A3744" stroke="none"/>
    <circle cx="123.6" cy="28.4" r="1.6" fill="#FFFFFF" stroke="none"/>
  </g>
</svg>
"""


def main() -> int:
	breeds = json.loads((ROOT / "data" / "breeds.json").read_text(encoding="utf-8"))
	rows = breeds if isinstance(breeds, list) else breeds.get("breeds", breeds)
	missing = [r["id"] for r in rows if r["id"] not in PALETTE]
	if missing:
		raise SystemExit("brak palety dla ras: %s" % ", ".join(missing))
	# Literowka w kolorze przeszlaby do pliku SVG i Godot wczytalby grafike
	# z czarna plama zamiast piora, wiec kazdy kolor sprawdzamy tutaj.
	for breed_id, colors in PALETTE.items():
		for color in colors:
			if not re.fullmatch(r"#[0-9A-Fa-f]{6}", color):
				raise SystemExit("rasa %s: '%s' nie jest kolorem" % (breed_id, color))
	for row in rows:
		breed_id = row["id"]
		light, base, dark, tail, comb = PALETTE[breed_id]
		slug = breed_id[:3]
		svg = TEMPLATE.format(breed=breed_id, slug=slug, light=light, base=base,
				dark=dark, tail=tail, comb=comb)
		path = OUT / ("rooster_%s.svg" % breed_id)
		path.write_text(svg, encoding="utf-8")
		print("zapisano %s" % path.relative_to(ROOT))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
