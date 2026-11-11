# Scripts

Repeatable automation.

- `install.sh`: builds the release app, checks its signature against the installed app's
  (so the Accessibility permission is kept), its entitlements and its binary, stamps it
  with the commit, and installs it to `/Applications`. `--check` stops before installing.
- `qa/lint-logi-boundary.sh`: enforces the boundary around `Mos/Logi/` and
  `Mos/Integration/`. Run it by hand after changes there; `LogiBoundaryEnforcementTests`
  runs it as part of the test suite.

Hand-run diagnostics that are not stable entry points live in `tools/`.
