#!/bin/bash
# Packages build/Blacktop.app into build/Blacktop.dmg: a window with the app,
# an Applications shortcut, and an arrow telling people to drag one onto the other.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Blacktop.app"
DMG="build/Blacktop.dmg"
RW_DMG="build/Blacktop-rw.dmg"
VOLUME="Blacktop"

[ -d "$APP" ] || ./scripts/build-app.sh

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"

# Retina-ready background: combine 1x and 2x into one TIFF.
swift scripts/dmg-background.swift "$STAGE/bg.png" 1
swift scripts/dmg-background.swift "$STAGE/bg@2x.png" 2
tiffutil -cathidpicheck "$STAGE/bg.png" "$STAGE/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
rm "$STAGE/bg.png" "$STAGE/bg@2x.png"

# Detach any leftover mount from a previous run.
[ -d "/Volumes/$VOLUME" ] && hdiutil detach "/Volumes/$VOLUME" -quiet

rm -f "$RW_DMG" "$DMG"
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW "$RW_DMG"
hdiutil attach -quiet -noautoopen "$RW_DMG"

# Lay out the Finder window. This is saved in the volume's .DS_Store.
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 740, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Blacktop.app" of container window to {140, 180}
        set position of item "Applications" of container window to {400, 180}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

sync
hdiutil detach -quiet "/Volumes/$VOLUME"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW_DMG"

echo "Built $DMG"
