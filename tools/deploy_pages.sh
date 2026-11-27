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
# W GitHub Actions adres z tokenem podaje workflow (DEPLOY_REMOTE).
REMOTE="${DEPLOY_REMOTE:-$(git -C "$PROJECT_DIR" remote get-url origin)}"
AUTHOR="${DEPLOY_AUTHOR:-Claude}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$BUILD_DIR/version.json" ] || { echo "BLAD: $BUILD_DIR nie wyglada na build (brak version.json)" >&2; exit 1; }
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$BUILD_DIR/version.json")"

git clone -q --depth 1 --branch gh-pages --single-branch "$REMOTE" "$WORK/site"
cd "$WORK/site"

# Pliki, ktore build tworzy od nowa za kazdym razem.
rm -f index.* wasm_gz_loader.js version.json
cp "$BUILD_DIR"/* .

# Stare pakiety: zostawiamy trzy najnowsze. "Najnowsze" = najwiekszy numer
# wdrozenia (ostatni czlon wersji, GITHUB_RUN_NUMBER), NIE sort -V po calej
# wersji: 13.0.1.22 jest wedlug sort -V "starsza" niz 13.2.21 i 27.11 skrypt
# skasowal pakiet, ktory wlasnie wdrozyl - gra konczyla sie bledem
# "Failed loading file pack-13.0.1.22.txt". Biezacej wersji nie ruszamy nigdy.
ls pack-*.txt 2>/dev/null | sed 's/^pack-\(.*\)\.txt$/\1/' \
	| awk -F. '{print $NF " " $0}' | sort -n | cut -d' ' -f2- | head -n -3 \
	| while read -r old; do
		[ "$old" = "$VERSION" ] && continue
		rm -f "pack-$old.txt"
	done
[ -f "pack-$VERSION.txt" ] || { echo "BLAD: brak pack-$VERSION.txt po sprzataniu" >&2; exit 1; }

git add -A
if git diff --cached --quiet; then
	echo "Nic do wdrozenia - na serwerze juz jest ta wersja."
	exit 0
fi
git -c user.email=noreply@anthropic.com -c user.name="$AUTHOR" \
	commit -q -m "Wersja $VERSION na GitHub Pages"
git push -q origin gh-pages
echo "Wdrozone: wersja $VERSION"
ls -la
