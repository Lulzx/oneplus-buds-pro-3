#!/bin/zsh
# Builds BudsBar.app (menu-bar only) into ./build
set -euo pipefail
cd "${0:A:h}"
swift build -c release
APP=build/BudsBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/BudsBar "$APP/Contents/MacOS/BudsBar"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.BudsBar</string>
  <key>CFBundleName</key><string>BudsBar</string>
  <key>CFBundleDisplayName</key><string>BudsBar</string>
  <key>CFBundleExecutable</key><string>BudsBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>BudsBar talks to your OnePlus Buds to show battery and change noise control and sound settings.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
# Login items need a stable location, so install to /Applications.
pkill -x BudsBar 2>/dev/null || true
rm -rf /Applications/BudsBar.app
cp -R "$APP" /Applications/BudsBar.app
echo "Installed /Applications/BudsBar.app"
