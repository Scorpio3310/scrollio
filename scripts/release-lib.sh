#!/bin/bash
#
# Functions of scripts/release.sh that do not need the Developer ID to be tried: signing
# Sparkle's helper programs, looking at the signature of every program in the app,
# writing the appcast, and filling and packing the disk image. release.sh sources this
# file; so can a test, with another certificate (an "Apple Development" one signs the
# same way), and so does scripts/dmg/preview.sh, which signs nothing.
#
# The caller provides:
#   fail <message>     prints the message and ends the run
#   LOG                a file the tools' output goes to
#   IDENTITY           the certificate to sign with (its SHA-1 or its name)
#   APP_NAME           "Scrollio"
#   RELEASES_URL       the GitHub releases page, without a slash at the end
#   REPO               the repository's folder (CHANGELOG.md, LICENSE and scripts/dmg
#                      are read there)

# "14.0" as the appcast wants it: "14.0.0".
three_part() { awk -F. '{ printf "%d.%d.%d\n", $1, $2, $3 }' <<< "$1"; }

# The part of CHANGELOG.md under "## <version>" (up to the next "## "), without the empty
# lines around it. Prints nothing when the file or the part is missing. (The versions are
# compared as texts: as numbers, awk takes "1.10" and "1.1" for the same.)
changelog_section() {
    [ -f "$REPO/CHANGELOG.md" ] || return 0
    awk -v version="$1" '
        /^## / { on = (($2 "") == (version "")); next }
        on { lines[n++] = $0 }
        END {
            first = 0
            while (first < n && lines[first] ~ /^[[:space:]]*$/) first++
            last = n - 1
            while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
            for (i = first; i <= last; i++) print lines[i]
        }
    ' "$REPO/CHANGELOG.md"
}

# Writes the appcast: one item, the version being released. The installed copies compare
# its build number (sparkle:version, the app's CFBundleVersion) with their own.
#   write_appcast <file> <version> <build> <minimum macOS> <EdDSA signature> <bytes> <notes file>
write_appcast() {
    local out="$1" version="$2" build="$3" minimum="$4" signature="$5" length="$6" notes="$7"
    {
        echo '<?xml version="1.0" encoding="utf-8"?>'
        echo '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
        echo '  <channel>'
        echo "    <title>${APP_NAME}</title>"
        echo "    <link>${RELEASES_URL}</link>"
        echo "    <description>New versions of ${APP_NAME}.</description>"
        echo '    <language>en</language>'
        echo '    <item>'
        echo "      <title>${APP_NAME} ${version}</title>"
        echo "      <link>${RELEASES_URL}/tag/v${version}</link>"
        echo "      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>"
        echo "      <sparkle:version>${build}</sparkle:version>"
        echo "      <sparkle:shortVersionString>${version}</sparkle:shortVersionString>"
        echo "      <sparkle:minimumSystemVersion>${minimum}</sparkle:minimumSystemVersion>"
        echo "      <sparkle:fullReleaseNotesLink>${RELEASES_URL}</sparkle:fullReleaseNotesLink>"
        if [ -s "$notes" ]; then
            # Markdown, as it is in CHANGELOG.md. "]]>" would end the CDATA section.
            printf '      <description sparkle:format="markdown"><![CDATA['
            sed 's/]]>/]]]]><![CDATA[>/g' "$notes"
            echo ']]></description>'
        fi
        echo "      <enclosure url=\"${RELEASES_URL}/download/v${version}/${APP_NAME}-${version}.dmg\" sparkle:edSignature=\"${signature}\" length=\"${length}\" type=\"application/octet-stream\"/>"
        echo '    </item>'
        echo '  </channel>'
        echo '</rss>'
    } > "$out"
    xmllint --noout "$out" >> "$LOG" 2>&1 || fail "the appcast is not well-formed XML (log: $LOG)"
}

# Signs Sparkle's helper programs inside the built app, then the framework, then the app.
#
# The build signs the framework it embeds, but not the programs inside it: the installer
# and the downloader services, Autoupdate and Updater.app arrive signed ad hoc. Each is
# signed here, innermost first; then the framework, and last the app again, because its
# signature names the framework's. Never with --deep: the downloader service keeps its own
# entitlements, and only it.
#   sign_sparkle_helpers <app>
sign_sparkle_helpers() {
    local app="$1" sparkle code helper before after
    sparkle="$app/Contents/Frameworks/Sparkle.framework"
    [ -d "$sparkle" ] || fail "the built app has no Sparkle.framework"
    code="$sparkle/Versions/$(readlink "$sparkle/Versions/Current")"
    for helper in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
        [ -e "$code/$helper" ] || fail "Sparkle.framework has no $helper: this script signs the helpers of Sparkle 2 by name"
    done
    # What macOS will compare the next version's signature with (the Accessibility
    # permission hangs on it): signing again must not change it.
    before="$(codesign -d -r- "$app" 2>/dev/null | grep '^designated' || true)"
    sign_one "$code/XPCServices/Installer.xpc"
    sign_one --preserve-metadata=entitlements "$code/XPCServices/Downloader.xpc"
    sign_one "$code/Autoupdate"
    sign_one "$code/Updater.app"
    sign_one "$sparkle"
    # The app keeps the requirement the build wrote into its signature. For a Developer ID
    # codesign would otherwise write its own default, which says the same in other words;
    # with it kept, every release has the very requirement of the one before.
    sign_one --preserve-metadata=entitlements,requirements "$app"
    after="$(codesign -d -r- "$app" 2>/dev/null | grep '^designated' || true)"
    [ -n "$after" ] && [ "$after" = "$before" ] \
        || fail "signing the app again changed its designated requirement: macOS would take an update for another app and ask for the Accessibility permission again"
}

# One signature: hardened runtime, and a secure timestamp from Apple's server (notarization
# asks for both). The last argument is what is signed.
sign_one() {
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@" >> "$LOG" 2>&1 \
        || fail "could not sign ${*: -1} (log: $LOG)"
}

# Looks at every program (Mach-O file) in the app: signed by a certificate of the kind
# <authority> ("Developer ID Application") for <team>, with the hardened runtime and a
# secure timestamp. Leaves their number in PROGRAMS.
#   check_programs <app> <authority> <team>
check_programs() {
    local app="$1" authority="$2" team="$3" file name info
    PROGRAMS=0
    while IFS= read -r -d '' file; do
        case "$(/usr/bin/file -b "$file")" in
            *Mach-O*) ;;
            *) continue ;;
        esac
        PROGRAMS=$((PROGRAMS + 1))
        name="${file#"$app"/}"
        info="$(codesign -dvv "$file" 2>&1)" || fail "$name has no signature codesign can read"
        grep -q "^Authority=${authority}: " <<< "$info" \
            || fail "$name is not signed with the ${authority} certificate"
        grep -q "^TeamIdentifier=${team}\$" <<< "$info" \
            || fail "$name is not signed for team ${team}"
        grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([a-z,-]*runtime' <<< "$info" \
            || fail "$name runs without the hardened runtime"
        grep -q '^Timestamp=' <<< "$info" \
            || fail "$name has no secure timestamp"
    done < <(find "$app" -type f -print0)
}

# --- The disk image ---------------------------------------------------------------------
# Opened, the image is a window: the app's icon, an arrow and the Applications folder on a
# picture. Finder reads that from two files on the image, which scripts/dmg holds ready:
# the picture, and the layout (Finder's ".DS_Store": the window's size, the icons' size
# and place, and which picture). scripts/README.md says how both are made. The layout
# names the items below, the volume and the picture's place by name: change a name here
# and in scripts/dmg/write-layout.swift together (ReleaseReadinessTests compares them).
DMG_PICTURE="scripts/dmg/background.tiff"
DMG_LAYOUT="scripts/dmg/DS_Store"

# Ends the run unless the picture and the layout of the image's window are there.
require_disk_image_window() {
    [ -s "$REPO/$DMG_PICTURE" ] \
        || fail "the picture of the disk image's window is missing: $DMG_PICTURE (scripts/README.md says how it is drawn)"
    [ -s "$REPO/$DMG_LAYOUT" ] \
        || fail "the layout of the disk image's window is missing: $DMG_LAYOUT (scripts/README.md says how it is written)"
}

# Fills <folder> with everything the image holds: the app, a link to Applications, the
# licence and the acknowledgements, and the window's picture and layout. The folder must
# be new or empty: what lies in it would be on the image too.
#   stage_disk_image <app> <folder>
stage_disk_image() {
    local app="$1" stage="$2"
    require_disk_image_window
    [ -d "$app" ] || fail "no app at $app"
    [ -s "$app/Contents/Resources/Acknowledgements.txt" ] \
        || fail "the app does not carry Acknowledgements.txt (Scrollio/Acknowledgements.txt)"
    [ -s "$REPO/LICENSE" ] || fail "no LICENSE in the repository"
    [ -z "$(ls -A "$stage" 2>/dev/null)" ] || fail "the folder for the disk image is not empty: $stage"
    mkdir -p "$stage/.background"
    ditto "$app" "$stage/${APP_NAME}.app"
    ln -s /Applications "$stage/Applications"
    cp "$REPO/LICENSE" "$stage/LICENSE.txt"
    cp "$app/Contents/Resources/Acknowledgements.txt" "$stage/Acknowledgements.txt"
    cp "$REPO/$DMG_PICTURE" "$stage/.background/background.tiff"
    cp "$REPO/$DMG_LAYOUT" "$stage/.DS_Store"
}

# Packs <folder> into a compressed, read-only image. The volume is named APP_NAME: the
# layout finds its picture by that name. The file system is asked for by name: left to
# itself, hdiutil takes the one its macOS prefers (APFS on macOS 27), and an image would
# differ with the Mac it was made on. HFS+ is what the layout's alias says.
#   make_disk_image <folder> <image>
make_disk_image() {
    hdiutil create -volname "$APP_NAME" -srcfolder "$1" -fs HFS+ -ov -format UDZO "$2" >> "$LOG" 2>&1 \
        || fail "could not create the disk image (log: $LOG)"
}
