#!/bin/zsh
# Arma la app de Windows x64: Electron oficial (verificado) + la app + icono.
set -e
cd "$(dirname "$0")"
# Versión: la da el workflow de release (VERSION=1.2.3, sin "v"); en local sale del último tag.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
export VERSION
V=42.11.16
ZIP=.cache/electron-v$V-win32-x64.zip
[[ -f $ZIP ]] || { echo "Falta $ZIP (descárgalo de las releases de Electron)"; exit 1; }
OUT="dist/MAD Equalizer"
rm -rf dist && mkdir -p "$OUT"
unzip -q "$ZIP" -d "$OUT"
mv "$OUT/electron.exe" "$OUT/MADEqualizer.exe"
rm -f "$OUT/resources/default_app.asar"
mkdir -p "$OUT/resources/app"
cp -R package.json main.js media.js preload.js renderer assets "$OUT/resources/app/"
node tools-icon.js "$OUT/MADEqualizer.exe"
echo "OK: $(du -sh "$OUT" | cut -f1) en $OUT"
