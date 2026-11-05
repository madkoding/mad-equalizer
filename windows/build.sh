#!/bin/zsh
# Genera out/MAD-Equalizer-<versión>-Windows.zip (instalador + README/LEEME) desde macOS o Linux.
# Requiere: node, makensis (brew install makensis), .cache/electron-v42.11.16-win32-x64.zip y vendor/EqualizerAPO-x64-1.4.2.exe
set -e
cd "$(dirname "$0")"
# Versión: la da el workflow de release (VERSION=1.2.3, sin "v"); en local sale del último tag.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
export VERSION
./pack.sh
mkdir -p out
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 makensis -V2 -DVERSION="$VERSION" installer/mad.nsi   # el makensis de Homebrew falla con otros locales
cd out
ZIP="MAD-Equalizer-$VERSION-Windows.zip"
rm -f "$ZIP"
for f in README.txt LEEME.txt; do sed "s/@VERSION@/$VERSION/g" "../installer/$f" > "$f"; done
zip -X -9 -q "$ZIP" "MAD-Equalizer-$VERSION-Setup.exe" README.txt LEEME.txt
rm README.txt LEEME.txt
echo "OK: $(pwd)/$ZIP ($(du -h "$ZIP" | cut -f1))"
