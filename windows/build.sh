#!/bin/zsh
# Genera out/MAD-Equalizer-2.0-Windows.zip (instalador + README/LEEME) desde macOS o Linux.
# Requiere: node, makensis (brew install makensis), .cache/electron-v42.11.16-win32-x64.zip y vendor/EqualizerAPO-x64-1.4.2.exe
set -e
cd "$(dirname "$0")"
./pack.sh
mkdir -p out
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 makensis -V2 installer/mad.nsi   # el makensis de Homebrew falla con otros locales
cd out
rm -f MAD-Equalizer-2.0-Windows.zip
cp ../installer/README.txt ../installer/LEEME.txt .
zip -X -9 -q MAD-Equalizer-2.0-Windows.zip MAD-Equalizer-2.0-Setup.exe README.txt LEEME.txt
rm README.txt LEEME.txt
echo "OK: $(pwd)/MAD-Equalizer-2.0-Windows.zip ($(du -h MAD-Equalizer-2.0-Windows.zip | cut -f1))"
