#!/bin/zsh
# Compila MAD Equalizer como app universal (Apple Silicon + Intel), con icono y fuentes.
set -e
cd "$(dirname "$0")"
APP="MAD Equalizer.app"
SRC=(Audio.swift Model.swift UI.swift)
BUILD=.build
rm -rf "$APP" "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $arch-apple-macos14.4 $SRC -o "$BUILD/MADEqualizer-$arch"
done
lipo -create "$BUILD"/MADEqualizer-* -output "$APP/Contents/MacOS/MADEqualizer"
cp fonts/*.ttf "$APP/Contents/Resources/"
cp art/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MADEqualizer</string>
<key>CFBundleIdentifier</key><string>local.eq16</string>
<key>CFBundleName</key><string>MAD Equalizer</string>
<key>CFBundleDisplayName</key><string>MAD Equalizer</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.0</string>
<key>CFBundleVersion</key><string>2.0</string>
<key>LSMinimumSystemVersion</key><string>14.4</string>
<key>LSApplicationCategoryType</key><string>public.app-category.music</string>
<key>NSHighResolutionCapable</key><true/>
<key>ATSApplicationFontsPath</key><string>.</string>
<key>NSAudioCaptureUsageDescription</key><string>MAD Equalizer necesita capturar el audio del sistema para ecualizarlo antes de enviarlo a tus altavoces o audífonos.</string>
</dict></plist>
EOF
codesign --force --deep --sign - "$APP"
echo "OK: $(pwd)/$APP ($(lipo -archs "$APP/Contents/MacOS/MADEqualizer"))"
