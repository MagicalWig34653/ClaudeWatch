#!/bin/sh
# Packages ClaudeWatch.app into a drag-to-install DMG with a background image,
# icon layout and volume icon. macOS only; uses hdiutil, tiffutil, SetFile and
# Finder (via osascript) to store the window layout.
#
#   Scripts/make-dmg.sh path/to/ClaudeWatch.app path/to/ClaudeWatch-1.0.0.dmg
set -eu

APP="$1"
OUT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VOLNAME="ClaudeWatch"
WORK="$(mktemp -d)"
MOUNT="$WORK/mount"
trap 'hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

[ -d "$APP" ] || { echo "No app at $APP" >&2; exit 66; }

# Staging folder: app, Applications link, hidden background and volume icon.
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/ClaudeWatch.app"
ln -s /Applications "$STAGE/Applications"
tiffutil -cathidpicheck "$ROOT/Artwork/dmg-background.png" "$ROOT/Artwork/dmg-background@2x.png" \
  -out "$STAGE/.background/background.tiff"
# Volume icon: the .icns Xcode compiled from the Icon Composer icon (AppIcon.icon).
ICON_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP/Contents/Info.plist" 2>/dev/null || true)"
ICNS="$APP/Contents/Resources/${ICON_NAME%.icns}.icns"
if [ -n "$ICON_NAME" ] && [ -f "$ICNS" ]; then
  cp "$ICNS" "$STAGE/.VolumeIcon.icns"
else
  echo "warning: app has no compiled .icns; the DMG will use the default volume icon" >&2
fi

# Writable image to arrange in Finder.
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg" >/dev/null
mkdir -p "$MOUNT"
hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen -mountpoint "$MOUNT" >/dev/null
[ -f "$MOUNT/.VolumeIcon.icns" ] && SetFile -a C "$MOUNT"

# Finder stores the layout in .DS_Store. The window is sized to the 660x400 background
# (plus the title bar); icon positions match the arrow drawn in the background.
osascript <<APPLESCRIPT
tell application "Finder"
  set dmg to (POSIX file "$MOUNT") as alias
  open dmg
  set win to container window of dmg
  set current view of win to icon view
  set toolbar visible of win to false
  set statusbar visible of win to false
  set bounds of win to {200, 120, 860, 548}
  set opts to icon view options of win
  set arrangement of opts to not arranged
  set icon size of opts to 128
  set text size of opts to 13
  set background picture of opts to file ".background:background.tiff" of dmg
  set position of item "ClaudeWatch.app" of dmg to {170, 190}
  set position of item "Applications" of dmg to {490, 190}
  update dmg without registering applications
  delay 2
  close win
end tell
APPLESCRIPT

# Wait until Finder has written the layout.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$MOUNT/.DS_Store" ] && break
  sleep 1
done
[ -f "$MOUNT/.DS_Store" ] || { echo "Finder did not store the DMG layout" >&2; exit 1; }

chmod -Rf go-w "$MOUNT" || true
sync
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT" >/dev/null
hdiutil verify "$OUT" >/dev/null
echo "Created $OUT"
