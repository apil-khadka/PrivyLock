#!/usr/bin/env bash
#
# Builds PrivyLock into a launchable .app bundle.
#
# Usage:
#   ./build.sh [release|debug]
#   ARCHS=arm64 ./build.sh release
#   SIGNING_IDENTITY="Developer ID Application: ..." ./build.sh release
#
# By default this produces a universal arm64 + x86_64 app. Local builds are
# ad-hoc signed; the release workflow supplies a Developer ID identity.

set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
ARCH_SELECTION="${ARCHS:-universal}"
APP="build/PrivyLock.app"

case "$ARCH_SELECTION" in
    universal) ARCH_LIST=(arm64 x86_64) ;;
    arm64|x86_64) ARCH_LIST=("$ARCH_SELECTION") ;;
    *) echo "Unsupported ARCHS value: $ARCH_SELECTION (use universal, arm64, or x86_64)" >&2; exit 2 ;;
esac

declare -a BINARIES=()
for arch in "${ARCH_LIST[@]}"; do
    scratch_path="$(mktemp -d "${TMPDIR:-/tmp}/privylock-${arch}.XXXXXX")"
    echo "==> Building $CONFIG for $arch"
    swift build -c "$CONFIG" --arch "$arch" --scratch-path "$scratch_path"
    binary="$scratch_path/${arch}-apple-macosx/$CONFIG/PrivyLock"
    if [[ ! -x "$binary" ]]; then
        echo "Build did not produce an executable at $binary" >&2
        exit 1
    fi
    BINARIES+=("$binary")
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "${#BINARIES[@]}" -eq 1 ]]; then
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/PrivyLock"
else
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/PrivyLock"
fi

cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Tell the app where its icon is (falls back to generic if no icon was built).
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true

SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "==> Ad-hoc signing $APP"
    codesign --force --deep --sign - "$APP"
else
    echo "==> Developer ID signing $APP"
    codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
fi

codesign --verify --deep --strict "$APP"
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/PrivyLock")"
echo "==> Done: $APP"
echo "    Run it with:  open $APP"
