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
  the notarization, so nothing is uploaded, and needs no tag. The root README, "Making a
  release", has the steps.
- `qa/lint-logi-boundary.sh`: enforces the boundary around `Scrollio/Logi/` and
  `Scrollio/Integration/`. Run it by hand after changes there;
  `LogiBoundaryEnforcementTests` runs it as part of the test suite, and `release.sh`
  before it builds.

Both build scripts name the project (`-project Scrollio.xcodeproj`), so a second
`.xcodeproj` in the folder does not stop them.

Hand-run diagnostics that are not stable entry points live in `tools/`.
