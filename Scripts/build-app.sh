#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

PRODUCT_NAME="PotatusHub"
APP_NAME="potatus hub"
VERSION="0.2.0"
BUILD_NUMBER="2"
BUILD_DIR=".build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

swift build -c release --arch arm64

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

BIN_PATH="$(swift build -c release --arch arm64 --show-bin-path)"
cp "$BIN_PATH/$PRODUCT_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [ -f "Resources/MenuBarIcon.png" ]; then
    cp "Resources/MenuBarIcon.png" "$APP_BUNDLE/Contents/Resources/MenuBarIcon.png"
fi

if [ -f "Resources/PotatusHubIcon-source.png" ]; then
    ICONSET_DIR="$BUILD_DIR/PotatusHubIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    sips -z 16 16 "Resources/PotatusHubIcon-source.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32 "Resources/PotatusHubIcon-source.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "Resources/PotatusHubIcon-source.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64 "Resources/PotatusHubIcon-source.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "Resources/PotatusHubIcon-source.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256 "Resources/PotatusHubIcon-source.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "Resources/PotatusHubIcon-source.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512 "Resources/PotatusHubIcon-source.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "Resources/PotatusHubIcon-source.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "Resources/PotatusHubIcon-source.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.bmminky.potatushub</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --verbose "$APP_BUNDLE"
echo "Done: $APP_BUNDLE"
