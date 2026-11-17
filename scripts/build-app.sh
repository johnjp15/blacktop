#!/bin/bash
# Builds Blackbar.app into ./build. Works with just the Xcode Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Blackbar.app"
VERSION="${VERSION:-0.1.0}"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Blackbar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Blackbar"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Blackbar</string>
    <key>CFBundleIdentifier</key>
    <string>com.johnjp15.Blackbar</string>
    <key>CFBundleName</key>
    <string>Blackbar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc sign so macOS will run it locally and SMAppService (launch at login) works.
codesign --force --sign - "$APP"

echo "Built $APP"
