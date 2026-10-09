#!/bin/sh
# Builds build/ScreenSwitch.app, a menu bar app without a Dock icon.
# Arguments go to swift build (CI passes --arch arm64 --arch x86_64).
# VERSION sets the bundle version (CI passes the tag without the v).
# SIGN_IDENTITY signs with a Developer ID and the hardened runtime that
# notarization requires; without it the app is signed ad hoc.
set -e
cd "$(dirname "$0")"
VERSION="${VERSION:-1.0}"
swift build -c release "$@"
BIN="$(swift build -c release "$@" --show-bin-path)"
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
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" "$APP"
else
    codesign --force -s - "$APP"
fi
echo "Built $APP"
