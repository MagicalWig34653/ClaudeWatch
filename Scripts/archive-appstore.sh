#!/bin/bash
# Archive ClaudeWatch for the Mac App Store / TestFlight and upload it to App Store Connect.
#
# Usage: Scripts/archive-appstore.sh [--no-upload] [build-number]
#   build-number   defaults to a UTC timestamp (YYMMDDHHMM) so every upload is unique
#
# Needs: Xcode signed in with the paid developer account (Settings > Accounts) and the app
# record (bundle ID de.linolaske.ClaudeWatch) created in App Store Connect.
# The App Store build is sandboxed (Config/ClaudeWatch-AppStore.entitlements); the DMG build
# from Scripts/make-dmg.sh stays unsandboxed.
set -euo pipefail

cd "$(dirname "$0")/.."
TEAM_ID="J2DU2P47XW"
# com.claudewatch.ClaudeWatch (DMG build) is registered to another team, so the App Store build overrides it.
BUNDLE_ID="de.linolaske.ClaudeWatch"
UPLOAD=1
if [ "${1:-}" = "--no-upload" ]; then UPLOAD=0; shift; fi
BUILD_NUMBER="${1:-$(date -u +%y%m%d%H%M)}"

ARCHIVE="build/AppStore/ClaudeWatch.xcarchive"
EXPORT_DIR="build/AppStore/export"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

xcodebuild archive \
  -project ClaudeWatch.xcodeproj -scheme ClaudeWatch -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGN_ENTITLEMENTS=Config/ClaudeWatch-AppStore.entitlements \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "Archive: $ARCHIVE (build $BUILD_NUMBER)"
codesign -d --entitlements - "$ARCHIVE/Products/Applications/ClaudeWatch.app" 2>&1 | grep -E "app-sandbox|network" || true

if [ "$UPLOAD" = 1 ]; then
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist Config/ExportOptions-AppStore.plist -allowProvisioningUpdates
  echo "Uploaded to App Store Connect. The build appears in TestFlight after processing."
else
  echo "Skipped upload (--no-upload)."
fi
