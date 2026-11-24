#!/usr/bin/env bash
# Wrzuca zbudowana gre na GitHub Pages (galaz gh-pages).
#
#   tools/build_web.sh /tmp/web_build
#   tools/deploy_pages.sh /tmp/web_build
#
# Zostawia na serwerze TRZY ostatnie pakiety gry (pack-<wersja>.txt).
# Przegladarka moze miec w pamieci podrecznej index.html sprzed kilku minut
# (GitHub Pages trzyma go do 10 minut), a ten wskazuje na pakiet poprzedniej
# wersji. Gdyby go nie bylo, gracz dostalby czarny ekran zamiast gry.
#
# Pliki engine.txt i pack.txt (bez numeru) to nazwy sprzed wersji 12.14.
# Zostaja na razie dla kart, ktore maja jeszcze w pamieci stary index.html.
# Mozna je usunac po kilku kolejnych wydaniach.
set -euo pipefail

BUILD_DIR="${1:?podaj katalog z buildem, np. /tmp/web_build}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="$(git -C "$PROJECT_DIR" remote get-url origin)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$BUILD_DIR/version.json" ] || { echo "BLAD: $BUILD_DIR nie wyglada na build (brak version.json)" >&2; exit 1; }
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$BUILD_DIR/version.json")"

git clone -q --depth 1 --branch gh-pages --single-branch "$REMOTE" "$WORK/site"
cd "$WORK/site"

# Pliki, ktore build tworzy od nowa za kazdym razem.
rm -f index.* wasm_gz_loader.js version.json
cp "$BUILD_DIR"/* .

# Stare pakiety: zostawiamy trzy najnowsze.
ls pack-*.txt 2>/dev/null | sed 's/^pack-\(.*\)\.txt$/\1/' | sort -V | head -n -3 \
	| while read -r old; do rm -f "pack-$old.txt"; done

git add -A
if git diff --cached --quiet; then
	echo "Nic do wdrozenia - na serwerze juz jest ta wersja."
	exit 0
fi
git -c user.email=noreply@anthropic.com -c user.name="Claude" \
	commit -q -m "Wersja $VERSION na GitHub Pages"
git push -q origin gh-pages
echo "Wdrozone: wersja $VERSION"
ls -la
