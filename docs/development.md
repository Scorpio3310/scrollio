# Building and releasing

## Build from source

You need a Mac with macOS 14 or later, Xcode 26 or later (the app icon is an Icon
Composer file) and an Apple Development signing identity; a free Apple account gives
one. Do not turn signing off: macOS ties the Accessibility permission to the code
signature.

The project signs for the author's team. To sign with yours, do not edit the project:

```bash
cp Local.xcconfig.example Local.xcconfig    # then put your Team ID into Local.xcconfig
```

`Local.xcconfig` is ignored by git, so the tree stays clean. `scripts/install.sh` passes
it to its build when it exists; for the plain `xcodebuild` commands below, add
`-xcconfig Local.xcconfig`. (In Xcode itself, choose your team under Signing &
Capabilities instead, and do not commit that change.) Without the file nothing is
different: the project's own settings are used.

To build the release app and install it in `/Applications`:

```bash
scripts/install.sh            # build, check, install, start
scripts/install.sh --check    # build and check only; nothing is installed
```

The script builds into `build/install` (or `$SCROLLIO_DERIVED_DATA`) and stamps the build
with its commit and date (shown under General). It installs a build only when:

- its signature verifies, is made with a certificate (not ad hoc) and has the same
  designated requirement as the installed app (a differently signed build would be asked
  for the Accessibility permission again; so a downloaded Scrollio has to be removed
  before a build of your own goes in its place, and the permission given again);
- its bundle identifier is `com.nikklemenc.Scrollio`;
- it carries no debugger entitlement (`get-task-allow`) and no code-coverage
  instrumentation.

It then quits the running copy, replaces `/Applications/Scrollio.app`, registers it again
with macOS so the Dock and Finder show the current icon, and opens it.

A build of your own does not update itself and makes no network request: only
`scripts/release.sh` gives a build the address of the update feed. (An update would put
the released app, signed by another certificate, in the place of yours, and macOS would
ask for the Accessibility permission again.) Take new versions with `git pull` and
build again.

Plain builds:

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build    # Scrollio Debug.app
xcodebuild -scheme Debug -configuration Release -destination 'platform=macOS' build  # Scrollio.app
```

The debug build is a separate app, `Scrollio Debug.app` (`com.nikklemenc.Scrollio.debug`).
It has two developer windows more (Scroll Monitor and Test Toasts, in the menu bar menu
with Option held) and links [Charts](https://github.com/danielgindi/Charts) for the
Scroll Monitor's graph; the release app is built without both. Both apps embed
[Sparkle](https://github.com/sparkle-project/Sparkle), the updater, which stays off in
a build without an update feed.

## For developers

```bash
pgrep -fl "Scrollio Debug.app"     # must print nothing: quit a running debug app first
xcodebuild -scheme Debug -destination 'platform=macOS' test
xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:ScrollioTests/<TestClassName>
scripts/qa/lint-logi-boundary.sh
```

The tests run inside `Scrollio Debug.app` with its startup side effects switched off:
the event taps and Logitech sessions are not started, the real settings are not written
and no login item is registered. Never add `CODE_SIGNING_ALLOWED=NO`: it re-signs the
debug app ad hoc, macOS then asks for the Accessibility permission again, and with a
running instance that prompt can freeze mouse and keyboard input. With a team of your
own, add `-xcconfig Local.xcconfig` to these commands too (see
[Build from source](#build-from-source)). Tests that talk to a real Logitech mouse run
only when asked for:

```bash
xcodebuild -scheme Debug -testPlan DebugWithDevice -destination 'platform=macOS' test
```

### Making a release

A build for other people's Macs is made with `scripts/release.sh`, from a tagged commit:

```bash
scripts/update-key.sh                   # the update key is in the keychain and is the app's
scripts/release.sh --check              # build, sign and check; nothing is uploaded (needs no tag)
git tag -a v1.0.1 -m "Scrollio 1.0.1"   # the version being released
scripts/release.sh                      # the same, then notarized by Apple, packed and signed as an update
git push origin v1.0.1                  # that one tag, by name
```

Then publish the GitHub release for that tag with **both** files of `build/release`:
`Scrollio-<version>.dmg` and `appcast.xml`, the second under exactly that name. The
installed copies ask for `releases/latest/download/appcast.xml`: a newest release
without that file means their check fails, and no copy learns of the version.
`Scrollio-<version>-notes.md` is the text for the release.

- **Before the tag.** Give the version its part in [CHANGELOG.md](../CHANGELOG.md)
  (`## 1.0.1`; what stands under `## Unreleased` becomes that part) and commit it: the
  update window shows that part to people with an older version, and the release notes
  start with it. Without it the script goes on and says
  that the window will not tell what is new.

- **Tags.** A release's version is its tag's: the commit must carry `v<version>`
  (`v1.0.0`), and the script refuses to release without it. The app and the image get
  that version; `MARKETING_VERSION` in the project is only what other builds show. Push
  the tag by name and never with `git push --tags`: a clone that also fetched the
  original project holds Mos's own tags (`1.0`, `1.0.0` and so on, without a `v`), which
  must not reach Scrollio's repository.
- **What it builds.** A universal Release app (Apple silicon and Intel) from an empty
  build folder, signed with the Developer ID certificate and stripped: an unstripped
  binary names the folders it was compiled in. Apple notarizes the app and the disk
  image.
- **Updates.** The script gives the build its update feed (no other build has one),
  signs Sparkle's helper programs with the Developer ID (they are distributed signed ad
  hoc, which Apple does not notarize), and after the image is notarized and stapled
  signs it with the update key and writes `appcast.xml` for it. The build number
  (`CFBundleVersion`, the number of commits) is what an installed copy compares: a
  release must be made from a commit later than the one before.
- **What it checks** before anything is uploaded: that the update key in the keychain is
  the one in `Scrollio/Info.plist` and can sign; the signature (Developer ID, team,
  hardened runtime, secure timestamp, no `get-task-allow`) of the app and of every
  program inside it; that signing the helpers left the app's designated requirement as
  the build made it (the Accessibility permission hangs on it); the feed and the key in
  the built app; both architectures, no code-coverage instrumentation, no debug map and
  no path of the build Mac anywhere in the app, debug symbols that belong to the
  binary, no Charts in the app, and the Logitech boundary lint. After the notarization:
  Gatekeeper's verdict on the app and on the image, and that the image's update
  signature verifies.
- **What it leaves** in `build/release`: `Scrollio-<version>.dmg` (the app, a link to
  Applications, `LICENSE.txt` and `Acknowledgements.txt`), `appcast.xml`,
  `Scrollio-<version>-notes.md` (the version's part of the changelog and the image's
  SHA-256) and `Scrollio-<version>.dSYM.zip`. The image and the appcast get their names
  only after the last check, so a run that fails leaves neither. Keep the `.dSYM.zip`
  and do not publish it: a crash report of that build cannot be read without it, and it
  holds the paths of the Mac it was built on.
- **What it needs**: a Developer ID Application certificate in the keychain,
  notarization credentials stored as the keychain profile `scrollio-notary`
  (`xcrun notarytool store-credentials "scrollio-notary" --team-id <team id>`), and the
  update key in the keychain. macOS asks once per tool whether it may use that key:
  "Always Allow".
- **The update key** is a key pair made once (`scripts/update-key.sh create`): the
  private half is in the login keychain of the Mac that makes releases, the public half
  is `SUPublicEDKey` in `Scrollio/Info.plist`. Keep one copy of the private half
  outside that Mac (`scripts/update-key.sh export <file>`, then into a password manager
  and the file deleted; `import <file>` brings it to another Mac). Whoever has it can
  sign what every installed copy would install. If it is lost, updates can go on with a
  new key as long as the image stays signed with the same Developer ID, which Sparkle
  accepts in place of the old key's signature: make a new key, put its public half into
  `Info.plist`, release. If the Developer ID changes as well, the installed copies
  cannot be updated and people have to download the new version by hand.

It installs nothing and leaves the project's signing settings as they are: the release
signature is not the development signature of the copy in `/Applications`. Before a
release is announced, open the image once on a Mac that never had Scrollio.

| Path | Contents |
| --- | --- |
| `Scrollio/` | The app: `ScrollCore`, `ButtonCore`, `InputEvent`, `Shortcut`, `Keys`, `Logi`, `Integration`, `MacPointer`, `Options`, `Managers`, `Update`, `Components`, `Windows`, `Utils` |
| `ScrollioTests/` | Unit tests (XCTest) |
| `Scrollio.xcodeproj/` | The Xcode project, schemes `Debug` and `Profile` |
| `scripts/` | `install.sh`, `release.sh` with `release-lib.sh`, `update-key.sh`, and in `qa/` the Logitech boundary lint (also run by a test) |
| `tools/` | Hand-run HID++ probes and a small regression harness (see its README before running a probe) |
| `assets/` | The pictures of this README |
| `AGENTS.md` | Rules for coding agents and contributors: build, tests, signing, module boundaries, strings |
| `CONTRIBUTING.md`, `SECURITY.md` | What to expect of issues and pull requests; how to report a security problem |
| `LICENSE`, `Scrollio/Acknowledgements.txt` | The licence with its notices; what Scrollio owes to other projects |
| `CHANGELOG.md` | What changed in each version: the text of the update window and of a release |
| `Local.xcconfig.example` | The template of `Local.xcconfig`, a Mac's own signing team |
