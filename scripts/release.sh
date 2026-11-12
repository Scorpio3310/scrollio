#!/bin/bash
#
# Builds the app for other people's Macs: a universal Release build (Apple silicon and
# Intel), stripped, signed with the Developer ID certificate, notarized by Apple and packed
# into a disk image.
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
# A release is made from a tagged commit, and its version is the tag's. The commit must
# carry the tag v<version> (v1.0.0); the app and the image get that version:
#
#   git tag -a v1.0.0 -m "Scrollio 1.0.0"
#   scripts/release.sh
#   git push origin v1.0.0          # that one tag, by name; never "git push --tags"
#
# The "v" is there because a clone can also hold the tags of the original Mos (1.0, 1.0.0
# and so on up to 4.x). Those must never reach Scrollio's repository, and no release may
# be made from one. --check runs without a tag; it then uses the project's version.
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
#   SCROLLIO_VERSION            which version, when the commit carries several v tags (1.0.0)
#
# What a release leaves in build/release (or SCROLLIO_RELEASE_DIR):
#   Scrollio-<version>.dmg        the image to publish: the app, a link to Applications,
#                                 LICENSE.txt and Acknowledgements.txt
#   Scrollio-<version>.dSYM.zip   the debug symbols of exactly this build. Keep it and do
#                                 not publish it: a crash report cannot be read without
#                                 it, and it holds the paths of the Mac it was built on.
# The image gets its name only after the last check: a run that fails leaves no image.
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
LOG="$DERIVED/release.log"
# Everything that is not finished lives here and goes when the script ends, however it
# ends. A signed image that Apple has not accepted yet looks finished and is not: opened
# on another Mac it shows Gatekeeper's "cannot be opened". It must never be left behind
# under the name of a release.
WORK="$DERIVED/unfinished"
STAGE="$WORK/image"

CHECK_ONLY=0
case "${1:-}" in
    "") ;;
    --check) CHECK_ONLY=1 ;;
    *) echo "usage: scripts/release.sh [--check]" >&2; exit 2 ;;
esac

fail() { echo "release: $*" >&2; exit 1; }

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Build settings from the environment would override the ones this script passes.
unset XCODE_XCCONFIG_FILE

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

# --- Version -------------------------------------------------------------------------
# The tags on this commit that name a version: v1.0.0, v1.2. No other tag counts (the
# original Mos's tags have no "v").
VERSION=""
TAGS="$(git tag --points-at HEAD --list 'v[0-9]*')"
if [ -n "${SCROLLIO_VERSION:-}" ]; then
    grep -qxF -- "v${SCROLLIO_VERSION}" <<< "$TAGS" \
        || fail "SCROLLIO_VERSION is ${SCROLLIO_VERSION}, but this commit does not carry the tag v${SCROLLIO_VERSION}"
    VERSION="$SCROLLIO_VERSION"
elif [ -n "$TAGS" ]; then
    [ "$(printf '%s\n' "$TAGS" | wc -l | tr -d ' ')" = 1 ] \
        || fail "this commit carries several version tags ($(printf '%s' "$TAGS" | tr '\n' ' ')): name the version to release in SCROLLIO_VERSION, without the v"
    VERSION="${TAGS#v}"
fi
if [ -n "$VERSION" ]; then
    grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$' <<< "$VERSION" \
        || fail "v${VERSION} is not a version macOS accepts: tag the commit v<major>.<minor>.<patch>, digits only (v1.0.0)"
elif [ "$CHECK_ONLY" = 0 ]; then
    cat >&2 <<'EOF'
release: this commit has no version tag, and a release is made from a tagged commit.
  Tag it with the version you are releasing (here 1.0.0), then run this script again:
      git tag -a v1.0.0 -m "Scrollio 1.0.0"
      scripts/release.sh
  When the image is good, push that one tag, by name:
      git push origin v1.0.0
  Never "git push --tags": a clone can also hold the tags of the original Mos (1.0, 1.0.0
  and so on), and those must not reach Scrollio's repository.
  (scripts/release.sh --check runs without a tag.)
EOF
    exit 1
fi

mkdir -p "$DERIVED"
: > "$LOG"

scripts/qa/lint-logi-boundary.sh >> "$LOG" 2>&1 \
    || fail "the Logitech boundary lint fails: scripts/qa/lint-logi-boundary.sh (log: $LOG)"

if [ "$CHECK_ONLY" = 0 ]; then
    # An image of this version from an earlier run goes first: if this run fails, nothing
    # may be left that looks like its result.
    rm -f "$DERIVED/${APP_NAME}-${VERSION}.dmg" "$DERIVED/${APP_NAME}-${VERSION}.dSYM.zip"

    # Ask for the credentials before the long build, not after it.
    xcrun notarytool history --keychain-profile "$PROFILE" >> "$LOG" 2>&1 \
        || fail "the notarization profile \"$PROFILE\" is missing or was refused (log: $LOG)"

    # The build that goes out starts from an empty build folder, not from what earlier
    # runs left there. (The package checkout next to it stays.)
    rm -rf "$DERIVED/Build"
fi

# --- Build ---------------------------------------------------------------------------
# The settings go in through a settings file, which overrides the project's own without
# touching them. The project gives CODE_SIGN_IDENTITY for sdk=macosx* as well, and that
# form cannot be written on xcodebuild's command line, so it is set here too.
# --timestamp asks Apple's server for a secure timestamp: notarization requires one.
# DEPLOYMENT_POSTPROCESSING makes the build strip the binary (STRIP_INSTALLED_PRODUCT)
# before it is signed. Unstripped, it carries its debug map: for every source file the
# folder it was compiled in, on this Mac, and every local symbol. The symbols stay in
# Scrollio.app.dSYM, next to the app.
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
DEPLOYMENT_POSTPROCESSING = YES
STRIP_INSTALLED_PRODUCT = YES
EOF
if [ -n "$VERSION" ]; then
    echo "MARKETING_VERSION = $VERSION" >> "$XCCONFIG"
fi

SHOWN_VERSION="$VERSION"
[ -n "$SHOWN_VERSION" ] || SHOWN_VERSION="(no tag: the project's version)"
echo "release: building ${APP_NAME} ${SHOWN_VERSION} ${COMMIT} (build ${COUNT}), universal, signed for team ${TEAM}…"
# -disableAutomaticPackageResolution: the package is taken as Package.resolved pins it; a
# release never moves that file by itself.
if ! xcodebuild -project "${APP_NAME}.xcodeproj" -scheme Debug -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$DERIVED" \
        -xcconfig "$XCCONFIG" \
        -disableAutomaticPackageResolution \
        CURRENT_PROJECT_VERSION="$COUNT" \
        SCROLLIO_BUILD_COMMIT="$COMMIT" \
        SCROLLIO_BUILD_DATE="$DATE" \
        build >> "$LOG" 2>&1; then
    grep -E "error:|\*\* BUILD" "$LOG" | tail -20 >&2 || true
    fail "the build failed (log: $LOG)"
fi
[ -d "$BUILT" ] || fail "no app at $BUILT"

# --- Checks --------------------------------------------------------------------------
# No check here pipes a tool into "grep -q": grep leaves at the first match, the tool is
# then ended by the closed pipe, and under pipefail the test reads as "no match". The
# tool's output goes to a variable or a file first.
BINARY="$BUILT/Contents/MacOS/${APP_NAME}"
DSYM="${BUILT}.dSYM"

SIGNATURE="$(codesign -dvv "$BUILT" 2>&1)" \
    || fail "codesign cannot read the built app's signature: ${SIGNATURE}"

codesign --verify --deep --strict "$BUILT" 2>/dev/null \
    || fail "the built app's signature does not verify"

BUILT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT/Contents/Info.plist")"
[ "$BUILT_ID" = "$BUNDLE_ID" ] || fail "bundle identifier is $BUILT_ID, expected $BUNDLE_ID"

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT/Contents/Info.plist")"
if [ -n "$VERSION" ]; then
    [ "$BUILT_VERSION" = "$VERSION" ] || fail "the built app says version $BUILT_VERSION, the tag says $VERSION"
fi
VERSION="$BUILT_VERSION"

grep -q '^Authority=Developer ID Application: ' <<< "$SIGNATURE" \
    || fail "the build is not signed with the Developer ID certificate"
grep -q "^TeamIdentifier=${TEAM}\$" <<< "$SIGNATURE" \
    || fail "the build is not signed for team ${TEAM}"
grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([a-z,-]*runtime' <<< "$SIGNATURE" \
    || fail "the hardened runtime is off: Apple does not notarize such a build"
grep -q '^Timestamp=' <<< "$SIGNATURE" \
    || fail "the signature has no secure timestamp: Apple does not notarize such a build"

ENTITLEMENTS="$(codesign -d --entitlements - "$BUILT" 2>/dev/null || true)"
case "$ENTITLEMENTS" in
    *get-task-allow*)
        fail "the build carries get-task-allow (a debugger could attach): is CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO still set for Release?" ;;
esac

LOAD_COMMANDS="$DERIVED/load-commands.txt"
otool -l "$BINARY" > "$LOAD_COMMANDS" 2>> "$LOG" || fail "otool cannot read the binary (log: $LOG)"
if grep -q -e "__llvm_prf" -e "__LLVM_COV" "$LOAD_COMMANDS"; then
    fail "the build is instrumented for code coverage (slower scroll path): are the test plans' codeCoverage options still false?"
fi

ARCHS_BUILT="$(lipo -archs "$BINARY")"
for arch in arm64 x86_64; do
    case " $ARCHS_BUILT " in
        *" $arch "*) ;;
        *) fail "the binary has no $arch slice (it has: $ARCHS_BUILT)" ;;
    esac
done

# Stripped: no debug map, and no path of this Mac anywhere in the app.
SYMBOLS="$DERIVED/symbols.txt"
nm -arch all -a "$BINARY" > "$SYMBOLS" 2>> "$LOG" || fail "nm cannot read the binary (log: $LOG)"
if grep -q ' OSO ' "$SYMBOLS"; then
    fail "the binary is not stripped (it still has its debug map): are DEPLOYMENT_POSTPROCESSING and STRIP_INSTALLED_PRODUCT still passed to the build?"
fi
# Each folder as it is written and as the system resolves it (/tmp is /private/tmp).
for folder in "$HOME" "$REPO" "$DERIVED"; do
    for path in "$folder" "$(cd "$folder" && pwd -P)"; do
        for needle in "$path" "${path#/private}"; do
            [ "${#needle}" -ge 4 ] || continue
            if grep -r -a -q -F -e "$needle" "$BUILT"; then
                fail "the built app contains the path $needle: everyone who downloads it could read where it was built"
            fi
        done
    done
done

# The symbols that were stripped: without them a crash report of this build is unreadable.
[ -d "$DSYM" ] || fail "no debug symbols at $DSYM"
BINARY_UUIDS="$(dwarfdump --uuid "$BINARY" 2>> "$LOG" | awk '{print $2, $3}' | sort)"
DSYM_UUIDS="$(dwarfdump --uuid "$DSYM" 2>> "$LOG" | awk '{print $2, $3}' | sort)"
[ -n "$BINARY_UUIDS" ] && [ "$BINARY_UUIDS" = "$DSYM_UUIDS" ] \
    || fail "the debug symbols at $DSYM are not those of this binary"

# Charts (DGCharts) draws the Scroll Monitor of the debug build only. The Release
# configuration leaves it out (EXCLUDED_SOURCE_FILE_NAMES), and the documents say so.
if [ -e "$BUILT/Contents/Resources/DGCharts_DGCharts.bundle" ] || grep -a -q -F "DGCharts" "$BINARY"; then
    fail "the release app contains DGCharts: is EXCLUDED_SOURCE_FILE_NAMES = DGCharts* still set for Release, and is every use of DGCharts inside #if DEBUG?"
fi

ACKNOWLEDGEMENTS="$BUILT/Contents/Resources/Acknowledgements.txt"
[ -s "$ACKNOWLEDGEMENTS" ] || fail "the app does not carry Acknowledgements.txt (Scrollio/Acknowledgements.txt)"
[ -s "$REPO/LICENSE" ] || fail "no LICENSE in the repository"

echo "release: built ${APP_NAME} ${VERSION} (${COUNT}) ${COMMIT}, ${DATE}: Developer ID signature, hardened runtime, timestamp, both architectures and a stripped binary are in order"

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

staple() {
    # Attaches Apple's ticket. Right after "Accepted" the ticket is sometimes not there
    # yet, so this tries three times before it gives up.
    local target="$1" try
    for try in 1 2 3; do
        if xcrun stapler staple "$target" >> "$LOG" 2>&1; then
            return 0
        fi
        if [ "$try" != 3 ]; then
            echo "release: the ticket for $(basename "$target") is not there yet; trying again in 20 seconds…"
            sleep 20
        fi
    done
    return 1
}

rm -rf "$WORK"
mkdir -p "$STAGE"
ditto "$BUILT" "$STAGE/${APP_NAME}.app"

# The app first, so that the copy inside the disk image carries its own ticket and opens
# on a Mac that is offline.
ZIP="$WORK/${APP_NAME}-${VERSION}.zip"
ditto -c -k --keepParent "$STAGE/${APP_NAME}.app" "$ZIP"
notarize "$ZIP"
rm -f "$ZIP"
staple "$STAGE/${APP_NAME}.app" \
    || fail "could not staple the ticket to the app (log: $LOG)"

# --- Disk image ----------------------------------------------------------------------
# Built in the unfinished folder; it moves to its name after the last check.
DMG="$DERIVED/${APP_NAME}-${VERSION}.dmg"
DSYM_ZIP="$DERIVED/${APP_NAME}-${VERSION}.dSYM.zip"
UNFINISHED_DMG="$WORK/${APP_NAME}-${VERSION}.dmg"
ln -s /Applications "$STAGE/Applications"
cp "$REPO/LICENSE" "$STAGE/LICENSE.txt"
cp "$ACKNOWLEDGEMENTS" "$STAGE/Acknowledgements.txt"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$UNFINISHED_DMG" >> "$LOG" 2>&1 \
    || fail "could not create the disk image (log: $LOG)"
codesign --sign "$IDENTITY" --timestamp "$UNFINISHED_DMG" >> "$LOG" 2>&1 \
    || fail "could not sign the disk image (log: $LOG)"
notarize "$UNFINISHED_DMG"
staple "$UNFINISHED_DMG" \
    || fail "could not staple the ticket to the disk image (log: $LOG)"

# --- What Gatekeeper will say --------------------------------------------------------
spctl --assess --type execute -vv "$STAGE/${APP_NAME}.app" >> "$LOG" 2>&1 \
    || fail "Gatekeeper rejects the app (log: $LOG)"
spctl --assess --type open --context context:primary-signature -vv "$UNFINISHED_DMG" >> "$LOG" 2>&1 \
    || fail "Gatekeeper rejects the disk image (log: $LOG)"
xcrun stapler validate "$UNFINISHED_DMG" >> "$LOG" 2>&1 \
    || fail "the disk image's ticket does not validate (log: $LOG)"

# --- Done: the symbols, then the image under its name --------------------------------
ditto -c -k --keepParent "$DSYM" "$WORK/symbols.zip" \
    || fail "could not pack the debug symbols"
mv "$WORK/symbols.zip" "$DSYM_ZIP"
mv "$UNFINISHED_DMG" "$DMG"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "release: ${APP_NAME} ${VERSION} (${COUNT}) ${COMMIT} is signed, notarized and stapled"
echo "release: $DMG"
echo "release: ${SIZE}, sha256 ${SHA}"
echo "release: $DSYM_ZIP holds the debug symbols of this build: keep it, do not publish it"
