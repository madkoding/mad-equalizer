#!/bin/zsh
# Crea MAD-Equalizer-<versión>.dmg: app + atajo a Aplicaciones + README/LEEME, con fondo y diseño de Finder.
set -e
cd "$(dirname "$0")"
APP="MAD Equalizer.app"
VOL="MAD Equalizer"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="MAD-Equalizer-$VERSION.dmg"
STAGE=.build/dmg-stage
RW=.build/rw.dmg

[[ -d "$APP" ]] || { echo "Primero ejecuta ./build.sh"; exit 1; }
rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp README.txt LEEME.txt "$STAGE/"
cp art/dmg_bg.tiff "$STAGE/.background/bg.tiff"

hdiutil detach "/Volumes/$VOL" -force -quiet 2>/dev/null || true
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -ov "$RW" -quiet
ATTACH=$(hdiutil attach -readwrite -noverify -noautoopen "$RW")
# La línea del volumen es la que trae punto de montaje (columnas separadas por tabulador).
DEV=$(echo "$ATTACH" | awk -F'\t' '$3 ~ /^\/Volumes\// {sub(/[ \t]+$/, "", $1); print $1}')
MNT=$(echo "$ATTACH" | awk -F'	' '$3 ~ /^\/Volumes\// {print $3}')
echo "Montado en: $MNT"

# Diseño de la ventana: fondo, iconos grandes, app a la izquierda y Aplicaciones a la derecha.
perl -e 'alarm 90; exec @ARGV' osascript <<EOF || echo "Aviso: no se pudo aplicar el diseño de Finder (el DMG funciona igual)."
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 96
        set text size of opts to 12
        set background picture of opts to file ".background:bg.tiff"
        set position of item "$APP" of container window to {160, 140}
        set position of item "Applications" of container window to {480, 140}
        set position of item "README.txt" of container window to {240, 300}
        set position of item "LEEME.txt" of container window to {400, 300}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Icono del volumen (después del diseño: Finder lo descarta si se copia antes)
cp art/AppIcon.icns "$MNT/.VolumeIcon.icns"
if xcrun -f SetFile >/dev/null 2>&1; then xcrun SetFile -a C "$MNT"; fi

rm -rf "$MNT/.fseventsd"
sync
hdiutil detach "$DEV" -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet
rm -f "$RW"
echo "OK: $(pwd)/$DMG ($(du -h "$DMG" | cut -f1))"
