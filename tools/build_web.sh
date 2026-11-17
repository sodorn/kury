#!/usr/bin/env bash
# Buduje wersje przegladarkowa gry.
#
#   tools/build_web.sh [katalog_wyjsciowy]
#
# Wymaga Godota 4.7.2 w PATH jako `godot` (albo zmiennej GODOT) oraz
# zainstalowanych szablonow eksportu dla tej wersji.
#
# Po eksporcie dwa pliki zmieniaja nazwe i format, bo hosting przyjmuje pliki
# do 20 MB i serwuje tylko wybrane rozszerzenia. Szczegoly i powody:
# tools/web/wasm_gz_loader.js.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$PROJECT_DIR/../web_build}"
GODOT="${GODOT:-godot}"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/index.* "$OUT_DIR"/engine.txt "$OUT_DIR"/pack.txt "$OUT_DIR"/wasm_gz_loader.js

"$GODOT" --headless --path "$PROJECT_DIR" --export-release "Web" "$OUT_DIR/index.html"

# Silnik: spakowany gzipem, rozpakowuje go loader w przegladarce.
gzip -9 -c "$OUT_DIR/index.wasm" > "$OUT_DIR/engine.txt"
rm -f "$OUT_DIR/index.wasm"
cp "$PROJECT_DIR/tools/web/wasm_gz_loader.js" "$OUT_DIR/"

# Pakiet z gra: sama zmiana nazwy. Silnikowi wskazujemy ja polem mainPack.
mv "$OUT_DIR/index.pck" "$OUT_DIR/pack.txt"
sed -i 's|"fileSizes":{"index.pck"|"mainPack":"pack.txt","fileSizes":{"pack.txt"|' "$OUT_DIR/index.html"
grep -q '"mainPack":"pack.txt"' "$OUT_DIR/index.html" || {
	echo "BLAD: nie udalo sie ustawic mainPack w index.html" >&2
	exit 1
}

echo "Gotowe: $OUT_DIR"
ls -la "$OUT_DIR"
