#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

UNIVERSAL="${UNIVERSAL:-0}"
if [ "${1:-}" = "--universal" ]; then
    UNIVERSAL=1
fi

if [ "$UNIVERSAL" = "1" ]; then
    echo "Building LiveScapes (release, universal arm64 + x86_64)..."
    swift build --disable-sandbox -c release --arch arm64 --arch x86_64
    BIN_PATH="$(swift build --disable-sandbox -c release --arch arm64 --arch x86_64 --show-bin-path)/LiveScapes"
else
    echo "Building LiveScapes (release)..."
    swift build --disable-sandbox -c release
    BIN_PATH="$(swift build --disable-sandbox -c release --show-bin-path)/LiveScapes"
fi
APP_DIR="$ROOT_DIR/build/LiveScapes.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/LiveScapes"
if [ -f "$ROOT_DIR/Assets/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>LiveScapes</string>
    <key>CFBundleExecutable</key>
    <string>LiveScapes</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.LiveScapes</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LiveScapes</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.5</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
echo "Built: $APP_DIR"
