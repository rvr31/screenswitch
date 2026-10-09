#!/bin/sh
# Builds build/ScreenSwitch.app, a menu bar app without a Dock icon.
set -e
cd "$(dirname "$0")"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP=build/ScreenSwitch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/ScreenSwitch" "$APP/Contents/MacOS/ScreenSwitch"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ScreenSwitch</string>
    <key>CFBundleIdentifier</key><string>nl.vanraan.screenswitch</string>
    <key>CFBundleName</key><string>ScreenSwitch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign -s - --force "$APP"
echo "Built $APP"
