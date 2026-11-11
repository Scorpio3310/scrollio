#!/bin/bash
#
# Builds the app for other people's Macs: a universal Release build (Apple silicon and
# Intel), signed with the Developer ID certificate, notarized by Apple and packed into a
# disk image.
#
#   scripts/release.sh              build, sign, check, notarize, staple, write the .dmg
#   scripts/release.sh --check      build, sign and check only; nothing is notarized
#
# It never installs or starts anything. The Developer ID signature is not the development
# signature of the copy in /Applications, so putting this build over that copy would make
# macOS ask for the Accessibility permission again (see scripts/install.sh). For the same
# reason the project's own signing settings are left alone: the identity is passed to this
# one build only.
#
# Needed once per Mac:
#   - a "Developer ID Application" certificate, with its private key, in the keychain
#   - notarization credentials, stored as a keychain profile:
#       xcrun notarytool store-credentials "scrollio-notary" --team-id <team id>
#
# Environment:
#   SCROLLIO_SIGN_IDENTITY      which Developer ID certificate, when the keychain has several
#   SCROLLIO_NOTARY_PROFILE     the keychain profile (default: scrollio-notary)
#   SCROLLIO_RELEASE_DIR        where everything is built (default: build/release)
#
# The build is stamped like scripts/install.sh stamps it (CFBundleVersion = number of
# commits, ScrollioBuildCommit, ScrollioBuildDate). A release is made from a commit: with
# uncommitted changes only --check runs.

set -euo pipefail

APP_NAME="Scrollio"
BUNDLE_ID="com.nikklemenc.Scrollio"
PROFILE="${SCROLLIO_NOTARY_PROFILE:-scrollio-notary}"

cd "$(dirname "$0")/.."
REPO="$PWD"
DERIVED="${SCROLLIO_RELEASE_DIR:-$REPO/build/release}"
BUILT="$DERIVED/Build/Products/Release/${APP_NAME}.app"
STAGE="$DERIVED/stage"
LOG="$DERIVED/release.log"

CHECK_ONLY=0
case "${1:-}" in
    "") ;;
    --check) CHECK_ONLY=1 ;;
    *) echo "usage: scripts/release.sh [--check]" >&2; exit 2 ;;
esac

fail() { echo "release: $*" >&2; exit 1; }

# --- The certificate -----------------------------------------------------------------
# One line per valid identity:   1) <sha-1> "Developer ID Application: Name (TEAMID)"
IDENTITIES="$(security find-identity -v -p codesigning | grep '"Developer ID Application: ' || true)"
if [ -n "${SCROLLIO_SIGN_IDENTITY:-}" ]; then
    IDENTITIES="$(printf '%s\n' "$IDENTITIES" | grep -F "$SCROLLIO_SIGN_IDENTITY" || true)"
fi
[ -n "$IDENTITIES" ] || fail "no Developer ID Application certificate with a private key in the keychain"
[ "$(printf '%s\n' "$IDENTITIES" | wc -l | tr -d ' ')" = 1 ] \
    || fail "several Developer ID Application certificates: name one in SCROLLIO_SIGN_IDENTITY"
IDENTITY="$(printf '%s\n' "$IDENTITIES" | awk '{print $2}')"
TEAM="$(printf '%s\n' "$IDENTITIES" | sed -E 's/.*\(([A-Z0-9]+)\)"$/\1/')"
[ -n "$IDENTITY" ] && [ -n "$TEAM" ] || fail "could not read the certificate's hash and team"

# --- Stamp ---------------------------------------------------------------------------
COMMIT="$(git rev-parse --short HEAD)"
if [ -n "$(git status --porcelain)" ]; then
    [ "$CHECK_ONLY" = 1 ] || fail "there are uncommitted changes: a release is made from a commit (--check still runs)"
    COMMIT="${COMMIT}+"
fi
COUNT="$(git rev-list --count HEAD)"
DATE="$(date +%Y-%m-%d)"

mkdir -p "$DERIVED"
: > "$LOG"

# Ask for the credentials before the long build, not after it.
if [ "$CHECK_ONLY" = 0 ]; then
    xcrun notarytool history --keychain-profile "$PROFILE" >> "$LOG" 2>&1 \
        || fail "the notarization profile \"$PROFILE\" is missing or was refused (log: $LOG)"
fi

# --- Build ---------------------------------------------------------------------------
# The signing settings go in through a settings file, which overrides the project's own
# without touching them. The project gives CODE_SIGN_IDENTITY for sdk=macosx* as well, and
# that form cannot be written on xcodebuild's command line, so it is set here too.
# --timestamp asks Apple's server for a secure timestamp: notarization requires one.
XCCONFIG="$DERIVED/release.xcconfig"
cat > "$XCCONFIG" <<EOF
ARCHS = arm64 x86_64
ONLY_ACTIVE_ARCH = NO
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = $IDENTITY
CODE_SIGN_IDENTITY[sdk=macosx*] = $IDENTITY
DEVELOPMENT_TEAM = $TEAM
PROVISIONING_PROFILE_SPECIFIER =
OTHER_CODE_SIGN_FLAGS = --timestamp
EOF

echo "release: building ${APP_NAME} ${COMMIT} (build ${COUNT}), universal, signed for team ${TEAM}…"
if ! xcodebuild -scheme Debug -configuration Release -destination 'generic/platform=macOS' \
        -derivedDataPath "$DERIVED" \
        -xcconfig "$XCCONFIG" \
        CURRENT_PROJECT_VERSION="$COUNT" \
        SCROLLIO_BUILD_COMMIT="$COMMIT" \
        SCROLLIO_BUILD_DATE="$DATE" \
        build >> "$LOG" 2>&1; then
    grep -E "error:|\*\* BUILD" "$LOG" | tail -20 >&2 || true
    fail "the build failed (log: $LOG)"
fi
[ -d "$BUILT" ] || fail "no app at $BUILT"

# --- Checks --------------------------------------------------------------------------
BINARY="$BUILT/Contents/MacOS/${APP_NAME}"
SIGNATURE="$(codesign -dvv "$BUILT" 2>&1)"

codesign --verify --deep --strict "$BUILT" 2>/dev/null \
    || fail "the built app's signature does not verify"

BUILT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT/Contents/Info.plist")"
[ "$BUILT_ID" = "$BUNDLE_ID" ] || fail "bundle identifier is $BUILT_ID, expected $BUNDLE_ID"

printf '%s\n' "$SIGNATURE" | grep -q '^Authority=Developer ID Application: ' \
    || fail "the build is not signed with the Developer ID certificate"
printf '%s\n' "$SIGNATURE" | grep -q "^TeamIdentifier=${TEAM}\$" \
    || fail "the build is not signed for team ${TEAM}"
printf '%s\n' "$SIGNATURE" | grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([a-z,-]*runtime' \
    || fail "the hardened runtime is off: Apple does not notarize such a build"
printf '%s\n' "$SIGNATURE" | grep -q '^Timestamp=' \
    || fail "the signature has no secure timestamp: Apple does not notarize such a build"

if codesign -d --entitlements - "$BUILT" 2>/dev/null | grep -q "get-task-allow"; then
    fail "the build carries get-task-allow (a debugger could attach): is CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO still set for Release?"
fi

if otool -l "$BINARY" | grep -q -e "__llvm_prf" -e "__LLVM_COV"; then
    fail "the build is instrumented for code coverage (slower scroll path): are the test plans' codeCoverage options still false?"
fi

ARCHS_BUILT="$(lipo -archs "$BINARY")"
for arch in arm64 x86_64; do
    case " $ARCHS_BUILT " in
        *" $arch "*) ;;
        *) fail "the binary has no $arch slice (it has: $ARCHS_BUILT)" ;;
    esac
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT/Contents/Info.plist")"
echo "release: built ${APP_NAME} ${VERSION} (${COUNT}) ${COMMIT}, ${DATE}: Developer ID signature, hardened runtime, timestamp and both architectures are in order"

if [ "$CHECK_ONLY" = 1 ]; then
    echo "release: --check: nothing was notarized ($BUILT)"
    exit 0
fi

# --- Notarize ------------------------------------------------------------------------
notarize() {
    # Uploads a file to Apple's notary service and waits for the verdict.
    local file="$1" result id status
    echo "release: sending $(basename "$file") to Apple's notary service (a few minutes)…"
    result="$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --output-format json 2>> "$LOG")" \
        || fail "could not submit $(basename "$file") for notarization (log: $LOG)"
    printf '%s\n' "$result" >> "$LOG"
    id="$(printf '%s' "$result" | plutil -extract id raw -o - - 2>/dev/null || true)"
    status="$(printf '%s' "$result" | plutil -extract status raw -o - - 2>/dev/null || true)"
    if [ "$status" != "Accepted" ]; then
        if [ -n "$id" ]; then
            xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
        fi
        fail "Apple did not accept $(basename "$file"): status ${status:-unknown}"
    fi
}

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$BUILT" "$STAGE/${APP_NAME}.app"

# The app first, so that the copy inside the disk image carries its own ticket and opens
# on a Mac that is offline.
ZIP="$DERIVED/${APP_NAME}-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$STAGE/${APP_NAME}.app" "$ZIP"
notarize "$ZIP"
rm -f "$ZIP"
xcrun stapler staple "$STAGE/${APP_NAME}.app" >> "$LOG" 2>&1 \
    || fail "could not staple the ticket to the app (log: $LOG)"

# --- Disk image ----------------------------------------------------------------------
DMG="$DERIVED/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >> "$LOG" 2>&1 \
    || fail "could not create the disk image (log: $LOG)"
codesign --sign "$IDENTITY" --timestamp "$DMG" >> "$LOG" 2>&1 \
    || fail "could not sign the disk image (log: $LOG)"
notarize "$DMG"
xcrun stapler staple "$DMG" >> "$LOG" 2>&1 \
    || fail "could not staple the ticket to the disk image (log: $LOG)"

# --- What Gatekeeper will say --------------------------------------------------------
spctl --assess --type execute -vv "$STAGE/${APP_NAME}.app" >> "$LOG" 2>&1 \
    || fail "Gatekeeper rejects the app (log: $LOG)"
spctl --assess --type open --context context:primary-signature -vv "$DMG" >> "$LOG" 2>&1 \
    || fail "Gatekeeper rejects the disk image (log: $LOG)"
xcrun stapler validate "$DMG" >> "$LOG" 2>&1 \
    || fail "the disk image's ticket does not validate (log: $LOG)"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "release: ${APP_NAME} ${VERSION} (${COUNT}) ${COMMIT} is signed, notarized and stapled"
echo "release: $DMG"
echo "release: ${SIZE}, sha256 ${SHA}"
