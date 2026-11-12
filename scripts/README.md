# Scripts

Repeatable automation.

- `install.sh`: builds the release app, checks its signature against the installed app's
  (so the Accessibility permission is kept), its entitlements and its binary, stamps it
  with the commit, and installs it to `/Applications`. `--check` stops before installing.
- `release.sh`: builds the app for other people's Macs: a universal Release build signed
  with the Developer ID certificate, notarized by Apple and packed into
  `build/release/Scrollio-<version>.dmg`. It installs nothing. `--check` stops before the
  notarization, so nothing is uploaded.
- `qa/lint-logi-boundary.sh`: enforces the boundary around `Scrollio/Logi/` and
  `Scrollio/Integration/`. Run it by hand after changes there;
  `LogiBoundaryEnforcementTests` runs it as part of the test suite.

Hand-run diagnostics that are not stable entry points live in `tools/`.
