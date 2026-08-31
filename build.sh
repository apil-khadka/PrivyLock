#!/usr/bin/env bash
#
# Builds PrivyLock into a launchable .app bundle.
#
# Usage:  ./build.sh [release|debug]
#
# Produces:
#   build/PrivyLock.app   (the runnable app - drag to /Applications if you like)

set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/PrivyLock.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BIN=".build/$( [ "$CONFIG" = "release" ] && echo "release" || echo "debug" )/PrivyLock"
cp "$BIN" "$APP/Contents/MacOS/PrivyLock"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true

# Tell the app where its icon is (falls back to generic if no icon was built).
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true

# Ad-hoc sign so the OS treats it as a proper app (required for some system prompts).
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "==> (warning) codesign skipped"

echo "==> Done: $APP"
echo "    Run it with:  open $APP"
