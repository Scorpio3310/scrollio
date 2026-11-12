#!/bin/bash
#
# The update key: the key pair a release's disk image is signed with, so that an installed
# Scrollio accepts it as an update (Sparkle, EdDSA). The private half lives in the login
# keychain of the Mac that makes releases; the public half is SUPublicEDKey in
# Scrollio/Info.plist, and with it in every released app.
#
#   scripts/update-key.sh                  show the keychain's public key, and whether it is the app's
#   scripts/update-key.sh create           make the key pair (once, ever) and print the public key
#   scripts/update-key.sh export <file>    write the private key to <file>, to keep it safe
#   scripts/update-key.sh import <file>    put a private key from <file> into the keychain
#
# Keep a copy of the private key somewhere safe (a password manager), and nowhere else:
#   - whoever has it can sign an update every installed Scrollio would install, on top of
#     the Accessibility permission the app holds;
#   - without it no new version reaches the installed copies as an update. (As long as
#     the releases stay signed with the same Developer ID, a lost key can be replaced by
#     a new one: see the README, "Making a release".)
# A file written by "export" is the key itself, unprotected: move it into the password
# manager and delete the file.
#
# macOS may ask whether the tool may use the key: allow it. The key is stored under the
# keychain account "scrollio" (SCROLLIO_UPDATE_KEY_ACCOUNT names another).

set -euo pipefail

APP_NAME="Scrollio"
ACCOUNT="${SCROLLIO_UPDATE_KEY_ACCOUNT:-scrollio}"

# A <file> is meant against the folder the script was called from, not the repository's.
CALLER_DIR="$PWD"
cd "$(dirname "$0")/.."
REPO="$PWD"
DERIVED="${SCROLLIO_RELEASE_DIR:-$REPO/build/release}"
INFO="$REPO/${APP_NAME}/Info.plist"

fail() { echo "update-key: $*" >&2; exit 1; }

# The key file as the caller named it, as a full path. It may not be inside the
# repository: an unprotected private key there is one "git add" away from being published.
key_file() {
    local file="$1" folder repository
    case "$file" in
        /*) ;;
        *) file="$CALLER_DIR/$file" ;;
    esac
    folder="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)" || fail "no folder $(dirname "$file")"
    repository="$(pwd -P)"
    case "$folder/" in
        "$repository"/*) fail "$file is inside the repository: keep the private key out of it (name a file somewhere else)" ;;
    esac
    printf '%s/%s\n' "$folder" "$(basename "$file")"
}

# Sparkle's tools come with its package (the version Package.resolved pins).
BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
if [ ! -x "$BIN/generate_keys" ]; then
    echo "update-key: fetching the packages (the key tool is Sparkle's)…"
    mkdir -p "$DERIVED"
    xcodebuild -project "${APP_NAME}.xcodeproj" -scheme Debug -resolvePackageDependencies \
        -derivedDataPath "$DERIVED" -disableAutomaticPackageResolution > "$DERIVED/update-key.log" 2>&1 \
        || fail "could not fetch the packages (log: $DERIVED/update-key.log)"
fi
[ -x "$BIN/generate_keys" ] || fail "Sparkle's key tool is not at $BIN"

app_key() { /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO" 2>/dev/null || true; }
# The public key of the keychain's key; nothing when there is none. (Without a key the
# tool prints an error on its standard output and fails: only what has the shape of a
# public key, 32 bytes in base64, is passed on.)
keychain_key() {
    local key
    key="$("$BIN/generate_keys" --account "$ACCOUNT" -p 2>/dev/null)" || return 0
    if grep -Eq '^[A-Za-z0-9+/]{43}=$' <<< "$key"; then
        printf '%s\n' "$key"
    fi
    return 0
}

compare() {
    local in_keychain="$1" in_app
    in_app="$(app_key)"
    echo "update-key: keychain (account \"$ACCOUNT\"): $in_keychain"
    echo "update-key: ${APP_NAME}/Info.plist:           ${in_app:-(none)}"
    if [ "$in_keychain" = "$in_app" ]; then
        echo "update-key: the same key: this Mac can sign updates the installed copies accept"
    else
        echo "update-key: NOT the same key. Put the keychain's public key into ${APP_NAME}/Info.plist as SUPublicEDKey" >&2
        echo "update-key: only if no released app carries the other one: copies that do would refuse every update" >&2
        return 1
    fi
}

case "${1:-show}" in
    show)
        [ $# -le 1 ] || fail "usage: scripts/update-key.sh [create | export <file> | import <file>]"
        KEY="$(keychain_key)"
        [ -n "$KEY" ] || fail "no update key in the keychain (account \"$ACCOUNT\"): \"import <file>\" brings one, \"create\" makes the first"
        compare "$KEY"
        ;;
    create)
        [ $# -eq 1 ] || fail "usage: scripts/update-key.sh create"
        [ -z "$(keychain_key)" ] || fail "the keychain already has an update key (account \"$ACCOUNT\"): nothing was made. Run scripts/update-key.sh to see it"
        "$BIN/generate_keys" --account "$ACCOUNT" > /dev/null \
            || fail "the key could not be made"
        KEY="$(keychain_key)"
        [ -n "$KEY" ] || fail "the key was made but cannot be read back from the keychain"
        echo "update-key: made. Its public key: $KEY"
        echo "update-key: now keep a copy of the private key: scripts/update-key.sh export <file>"
        compare "$KEY" || true
        ;;
    export)
        [ $# -eq 2 ] || fail "usage: scripts/update-key.sh export <file>"
        FILE="$(key_file "$2")"
        [ ! -e "$FILE" ] || fail "$FILE exists: name a new file"
        ( umask 077; "$BIN/generate_keys" --account "$ACCOUNT" -x "$FILE" ) \
            || fail "the key could not be written"
        echo "update-key: the private key is in $FILE (readable by you only)."
        echo "update-key: move it into your password manager and delete the file: it is the key itself, unprotected."
        ;;
    import)
        [ $# -eq 2 ] || fail "usage: scripts/update-key.sh import <file>"
        FILE="$(key_file "$2")"
        [ -f "$FILE" ] || fail "no file $FILE"
        "$BIN/generate_keys" --account "$ACCOUNT" -f "$FILE" \
            || fail "the key could not be put into the keychain"
        KEY="$(keychain_key)"
        [ -n "$KEY" ] || fail "the key was imported but cannot be read back from the keychain"
        compare "$KEY"
        ;;
    *)
        fail "usage: scripts/update-key.sh [create | export <file> | import <file>]"
        ;;
esac
