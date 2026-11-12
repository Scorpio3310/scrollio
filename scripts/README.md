# Scripts

Repeatable automation.

- `install.sh`: builds the release app, checks its signature against the installed app's
  (so the Accessibility permission is kept), its entitlements and its binary, stamps it
  with the commit, and installs it to `/Applications`. `--check` stops before installing.
  A `Local.xcconfig` in the repository root (ignored by git, template
  `Local.xcconfig.example`) is passed to the build: another Mac's signing team.
- `release.sh`: builds the app for other people's Macs, from a commit tagged `v<version>`:
  a universal Release build, stripped, signed with the Developer ID certificate, notarized
  by Apple and packed into `build/release/Scrollio-<version>.dmg`, with the debug symbols
  next to it in `Scrollio-<version>.dSYM.zip` (keep it, do not publish it). The image
  gets its name only after the last check. It installs nothing. `--check` stops before
  the notarization, so nothing is uploaded, and needs no tag. It also makes the release
  an update: the build gets its update feed, Sparkle's helper programs are signed with
  the Developer ID, and the finished image is signed with the update key and described
  in `build/release/appcast.xml`, which is published with the image. The root README,
  "Making a release", has the steps.
- `release-lib.sh`: the functions of `release.sh` that can be tried without the
  Developer ID (signing Sparkle's helpers, looking at every program's signature, writing
  the appcast). `release.sh` sources it; it is not run by itself.
- `update-key.sh`: the update key, whose private half is in the login keychain and
  whose public half is `SUPublicEDKey` in `Scrollio/Info.plist`. Without an argument it
  shows the keychain's public key and whether it is the app's; `create` makes the key
  (once, ever), `export <file>` and `import <file>` move the private half.
- `qa/lint-logi-boundary.sh`: enforces the boundary around `Scrollio/Logi/` and
  `Scrollio/Integration/`. Run it by hand after changes there;
  `LogiBoundaryEnforcementTests` runs it as part of the test suite, and `release.sh`
  before it builds.

Every script that calls `xcodebuild` names the project (`-project Scrollio.xcodeproj`),
so a second `.xcodeproj` in the folder does not stop it.

Hand-run diagnostics that are not stable entry points live in `tools/`.
