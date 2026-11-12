#!/bin/bash
#
# Builds a sample disk image, to look at its window without making a release.
#
#   scripts/dmg/preview.sh                        with a built Scrollio.app, if there is one
#   scripts/dmg/preview.sh <path to Scrollio.app> with that app
#
# The image is filled and packed by the functions scripts/release.sh uses
# (stage_disk_image and make_disk_image in scripts/release-lib.sh), so it holds what a
# release's image holds and opens as the same window. Nothing else of a release happens:
# nothing is built, signed, notarized or read from the keychain, and the image is not for
# anyone's Mac but this one.
#
# Without an argument the app is the first of: the release build (build/release), the
# install build (build/install), the installed copy (/Applications). When there is none,
# a stand-in named Scrollio.app takes its place: an empty app with the generic icon,
# enough to see where the icons sit.
#
# The script only writes build/dmg-preview/Scrollio-preview.dmg and says where it is; it
# opens nothing. To look, open the image in Finder. An image named Scrollio that is
# already open must be ejected first: Finder finds the window's picture by the volume's
# name, and would take it from the image that was opened first.

set -euo pipefail

APP_NAME="Scrollio"

CALLER_DIR="$PWD"
cd "$(dirname "$0")/../.."
REPO="$PWD"
OUT="$REPO/build/dmg-preview"
LOG="$OUT/preview.log"
IMAGE="$OUT/${APP_NAME}-preview.dmg"

fail() { echo "preview: $*" >&2; exit 1; }

case "$#" in
    0) APP="" ;;
    1) APP="$1" ;;
    *) echo "usage: scripts/dmg/preview.sh [<path to ${APP_NAME}.app>]" >&2; exit 2 ;;
esac
# A path that does not start at the root is meant from the folder the script was called in.
case "$APP" in
    ""|/*) ;;
    *) APP="$CALLER_DIR/$APP" ;;
esac

# shellcheck source=scripts/release-lib.sh
. "$REPO/scripts/release-lib.sh"

mkdir -p "$OUT"
: > "$LOG"
# Only what this script made itself goes: the folder the image is filled from, the
# stand-in and the image of the run before.
rm -rf "$OUT/image" "$OUT/stand-in" "$IMAGE"

if [ -n "$APP" ]; then
    [ -d "$APP" ] || fail "no app at $APP"
else
    for found in "$REPO/build/release/Build/Products/Release/${APP_NAME}.app" \
                 "$REPO/build/install/Build/Products/Release/${APP_NAME}.app" \
                 "/Applications/${APP_NAME}.app"; do
        if [ -d "$found" ]; then
            APP="$found"
            break
        fi
    done
fi

if [ -z "$APP" ]; then
    # The stand-in: a bundle Finder shows as an app. Its program does nothing, and its
    # identifier is not Scrollio's, so macOS never takes it for the real app.
    APP="$OUT/stand-in/${APP_NAME}.app"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.nikklemenc.Scrollio.dmg-preview-stand-in</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0</string>
</dict>
</plist>
EOF
    printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/MacOS/${APP_NAME}"
    chmod +x "$APP/Contents/MacOS/${APP_NAME}"
    cp "$REPO/${APP_NAME}/Acknowledgements.txt" "$APP/Contents/Resources/Acknowledgements.txt"
    echo "preview: no built ${APP_NAME}.app found: the image gets a stand-in with the generic app icon"
else
    echo "preview: the app is $APP"
fi

stage_disk_image "$APP" "$OUT/image"
make_disk_image "$OUT/image" "$IMAGE"
rm -rf "$OUT/image" "$OUT/stand-in"

echo "preview: $IMAGE"
echo "preview: unsigned and not notarized: for looking at the window on this Mac only"
echo "preview: to look, open it in Finder:  open \"$IMAGE\""
