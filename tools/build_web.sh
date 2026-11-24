#!/usr/bin/env bash
# Buduje wersje przegladarkowa gry.
#
#   tools/build_web.sh [katalog_wyjsciowy]
#
# Wymaga Godota 4.7.2 w PATH jako `godot` (albo zmiennej GODOT) oraz
# zainstalowanych szablonow eksportu dla tej wersji.
#
# Po eksporcie pliki zmieniaja nazwe i format, bo hosting przyjmuje pliki
# do 20 MB i serwuje tylko wybrane rozszerzenia. Szczegoly i powody:
# tools/web/wasm_gz_loader.js.
#
# KAZDA WERSJA GRY MA WLASNE NAZWY PLIKOW. Wczesniej gra ladowala sie zawsze
# spod "pack.txt" i "engine.txt", wiec przegladarka trzymala stare pliki
# w pamieci podrecznej i po wdrozeniu dalej chodzila stara wersja.
#
#   pack-<wersja gry>.txt      pakiet z gra, zmienia sie przy kazdym wydaniu
#   engine-<wersja Godota>.txt silnik, zmienia sie tylko z wersja Godota
#   wasm_gz_loader.js?v=...     skrypty z numerem wersji w adresie
#   version.json                numer wersji dla juz otwartych kart
#                               (services/updater.gd)
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$PROJECT_DIR/../web_build}"
GODOT="${GODOT:-godot}"

GAME_VERSION="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$PROJECT_DIR/project.godot")"
GODOT_VERSION="$("$GODOT" --version 2>/dev/null | head -1 | cut -d. -f1-3)"
[ -n "$GAME_VERSION" ] || { echo "BLAD: brak config/version w project.godot" >&2; exit 1; }
[ -n "$GODOT_VERSION" ] || { echo "BLAD: nie odczytalem wersji Godota" >&2; exit 1; }
PACK_FILE="pack-$GAME_VERSION.txt"
ENGINE_FILE="engine-$GODOT_VERSION.txt"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/index.* "$OUT_DIR"/engine*.txt "$OUT_DIR"/pack*.txt \
	"$OUT_DIR"/wasm_gz_loader.js "$OUT_DIR"/version.json

"$GODOT" --headless --path "$PROJECT_DIR" --export-release "Web" "$OUT_DIR/index.html"

# Silnik: spakowany gzipem, rozpakowuje go loader w przegladarce.
gzip -9 -n -c "$OUT_DIR/index.wasm" > "$OUT_DIR/$ENGINE_FILE"
rm -f "$OUT_DIR/index.wasm"
sed "s|var ENGINE_FILE = \"engine.txt\";|var ENGINE_FILE = \"$ENGINE_FILE\";|" \
	"$PROJECT_DIR/tools/web/wasm_gz_loader.js" > "$OUT_DIR/wasm_gz_loader.js"

# Pakiet z gra: nazwa z numerem wersji. Silnikowi wskazujemy go polem mainPack.
mv "$OUT_DIR/index.pck" "$OUT_DIR/$PACK_FILE"
sed -i "s|\"fileSizes\":{\"index.pck\"|\"mainPack\":\"$PACK_FILE\",\"fileSizes\":{\"$PACK_FILE\"|" \
	"$OUT_DIR/index.html"
# Skrypty: numer wersji w adresie, zeby nie przyszly z pamieci podrecznej.
sed -i "s|src='wasm_gz_loader.js'|src='wasm_gz_loader.js?v=$GAME_VERSION'|" "$OUT_DIR/index.html"
sed -i "s|src=\"index.js\"|src=\"index.js?v=$GODOT_VERSION\"|" "$OUT_DIR/index.html"

printf '{"version": "%s"}\n' "$GAME_VERSION" > "$OUT_DIR/version.json"

# Kazda podmiana MUSI sie udac. Cichy brak ktorejs to stara wersja u graczy.
check() {
	grep -q "$1" "$2" || { echo "BLAD: $3" >&2; exit 1; }
}
check "\"mainPack\":\"$PACK_FILE\"" "$OUT_DIR/index.html" "mainPack nie wskazuje $PACK_FILE"
check "wasm_gz_loader.js?v=$GAME_VERSION" "$OUT_DIR/index.html" "loader bez numeru wersji"
check "index.js?v=$GODOT_VERSION" "$OUT_DIR/index.html" "index.js bez numeru wersji"
check "\"$ENGINE_FILE\"" "$OUT_DIR/wasm_gz_loader.js" "loader nie zna nazwy silnika"
check "\"$GAME_VERSION\"" "$OUT_DIR/version.json" "version.json bez wersji"

echo "Gotowe: $OUT_DIR  (gra $GAME_VERSION, silnik $GODOT_VERSION)"
ls -la "$OUT_DIR"
