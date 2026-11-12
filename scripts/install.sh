#!/bin/bash
#
# Builds the release app, checks that it is a build macOS will keep trusting, and installs
# it to /Applications.
#
#   scripts/install.sh              build, check, install, start
#   scripts/install.sh --check      build and check only; nothing is installed
#
# Why the checks: Scrollio's event taps need the Accessibility permission, and macOS ties
# that permission to the app's code signature. A build signed differently (ad hoc, another
# certificate) would be asked for the permission again; with an event tap running, that
# prompt can block all mouse and keyboard input (see AGENTS.md). So a build whose signature
# does not match the installed app is refused here instead of installed.
#
# The build is stamped with the commit it was made from (CFBundleVersion = number of
# commits, ScrollioBuildCommit, ScrollioBuildDate), shown under General in Settings.
#
# The project signs for its author's team. To build with your own, do not edit the project:
# copy Local.xcconfig.example to Local.xcconfig (ignored by git) and put your team there.
# This script passes that file to the build when it exists.
#
# Environment:
#   SCROLLIO_DERIVED_DATA       where it builds (default: build/install)

set -euo pipefail

APP_NAME="Scrollio"
BUNDLE_ID="com.nikklemenc.Scrollio"
DEST="/Applications/${APP_NAME}.app"

cd "$(dirname "$0")/.."
REPO="$PWD"
DERIVED="${SCROLLIO_DERIVED_DATA:-$REPO/build/install}"
BUILT="$DERIVED/Build/Products/Release/${APP_NAME}.app"
LOG="$DERIVED/install-build.log"

CHECK_ONLY=0
case "${1:-}" in
    "") ;;
    --check) CHECK_ONLY=1 ;;
    *) echo "usage: scripts/install.sh [--check]" >&2; exit 2 ;;
esac

fail() { echo "install: $*" >&2; exit 1; }

requirement() {
    # The designated requirement: what macOS compares when it decides whether an updated
    # app is still the app the user gave a permission to.
    codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p'
}

# --- Stamp ---------------------------------------------------------------------------
COMMIT="$(git rev-parse --short HEAD)"
if [ -n "$(git status --porcelain)" ]; then
    COMMIT="${COMMIT}+"          # built with uncommitted changes
fi
COUNT="$(git rev-list --count HEAD)"
DATE="$(date +%Y-%m-%d)"

# --- Build ---------------------------------------------------------------------------
# Local.xcconfig: this Mac's own build settings (the signing team of someone who is not the
# author). Its settings override the project's. Without the file nothing is passed.
LOCAL_SETTINGS=()
if [ -f "$REPO/Local.xcconfig" ]; then
    LOCAL_SETTINGS=(-xcconfig "$REPO/Local.xcconfig")
    echo "install: using the build settings in Local.xcconfig"
fi

mkdir -p "$DERIVED"
echo "install: building ${APP_NAME} ${COMMIT} (build ${COUNT})…"
# The project is named: a second .xcodeproj in the folder (a leftover of an older name)
# would otherwise stop xcodebuild.
if ! xcodebuild -project "${APP_NAME}.xcodeproj" -scheme Debug -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" \
        ${LOCAL_SETTINGS[@]+"${LOCAL_SETTINGS[@]}"} \
        CURRENT_PROJECT_VERSION="$COUNT" \
        SCROLLIO_BUILD_COMMIT="$COMMIT" \
        SCROLLIO_BUILD_DATE="$DATE" \
        build > "$LOG" 2>&1; then
    grep -E "error:|\*\* BUILD" "$LOG" | tail -20 >&2 || true
    fail "the build failed (log: $LOG)"
fi
[ -d "$BUILT" ] || fail "no app at $BUILT"

# --- Checks --------------------------------------------------------------------------
# No check here pipes a tool into "grep -q": grep leaves at the first match, the tool is
# then ended by the closed pipe, and under pipefail the test reads as "no match". The
# tool's output goes to a variable or a file first.
BINARY="$BUILT/Contents/MacOS/${APP_NAME}"

codesign --verify --deep --strict "$BUILT" 2>/dev/null \
    || fail "the built app's signature does not verify"

BUILT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT/Contents/Info.plist")"
[ "$BUILT_ID" = "$BUNDLE_ID" ] || fail "bundle identifier is $BUILT_ID, expected $BUNDLE_ID"

NEW_REQ="$(requirement "$BUILT")"
[ -n "$NEW_REQ" ] || fail "the built app has no designated requirement (is it signed ad hoc?)"
case "$NEW_REQ" in
    *"certificate leaf"*) ;;
    *) fail "the built app is not signed with a certificate (ad hoc?): $NEW_REQ" ;;
esac
if [ -d "$DEST" ]; then
    OLD_REQ="$(requirement "$DEST")"
    if [ "$NEW_REQ" != "$OLD_REQ" ]; then
        echo "installed: $OLD_REQ" >&2
        echo "built:     $NEW_REQ" >&2
        fail "the signature differs from the installed app's: macOS would ask for Accessibility again. Not installed."
    fi
fi

ENTITLEMENTS="$(codesign -d --entitlements - "$BUILT" 2>/dev/null || true)"
case "$ENTITLEMENTS" in
    *get-task-allow*)
        fail "the build carries get-task-allow (a debugger could attach): is CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO still set for Release?" ;;
esac

LOAD_COMMANDS="$DERIVED/load-commands.txt"
otool -l "$BINARY" > "$LOAD_COMMANDS" || fail "otool cannot read the binary"
if grep -q -e "__llvm_prf" -e "__LLVM_COV" "$LOAD_COMMANDS"; then
    fail "the build is instrumented for code coverage (slower scroll path): are the test plans' codeCoverage options still false?"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT/Contents/Info.plist")"
echo "install: built ${APP_NAME} ${VERSION} (${COUNT}) ${COMMIT}, ${DATE}: signature, entitlements and binary are in order"

if [ "$CHECK_ONLY" = 1 ]; then
    echo "install: --check: nothing installed ($BUILT)"
    exit 0
fi

# --- Install -------------------------------------------------------------------------
# Quit the running copy the ordinary way, so it gives the mouse's buttons back and lets go
# of its event taps; only then replace it.
if pgrep -x "$APP_NAME" > /dev/null; then
    osascript -e "quit app id \"$BUNDLE_ID\"" > /dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "$APP_NAME" > /dev/null || break
        sleep 0.5
    done
    if pgrep -x "$APP_NAME" > /dev/null; then
        echo "install: the running copy did not quit; ending it"
        pkill -x "$APP_NAME" || true
        sleep 1
    fi
fi

rm -rf "${DEST}.new"
ditto "$BUILT" "${DEST}.new"
rm -rf "$DEST"
mv "${DEST}.new" "$DEST"

# The Dock and Finder show this build's icon only when the system sees a changed app.
# ditto keeps the built bundle's modification date, which can be older than an icon that
# changed inside it, so the system's icon cache kept the old icon. A fresh date and a new
# registration with LaunchServices make it read the bundle again. The Dock is not
# restarted here.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
touch "$DEST"
"$LSREGISTER" -f "$DEST" \
    || echo "install: could not register ${APP_NAME} with LaunchServices; the Dock may show the old icon" >&2

open "$DEST"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "$APP_NAME" > /dev/null && break
    sleep 0.5
done
pgrep -x "$APP_NAME" > /dev/null || fail "installed, but ${APP_NAME} did not start"
echo "install: ${APP_NAME} ${VERSION} (${COUNT}) ${COMMIT} is installed and running"
