# AGENTS.md

The single guidance file for coding agents in this repository. Tool-specific entry files
(`CLAUDE.md`) only point here; do not keep a second copy of these rules anywhere.

## Priority

1. The user's current request and the system or tool safety rules.
2. This file.
3. `.agents/docs/code-map.md` and `LOCALIZATION.md`.
4. The current sources, the Xcode project and the test plans.
5. `docs/` and `CHANGELOG.md`. These are history, mostly from the original project:
   background only, never the source for commands, structure or scope.

## Before you start

1. Read this file, then only the sources, tests and docs the task needs.
2. Run `git status --short` and keep changes that are already there.

## The project

- Scrollio is a macOS menu-bar app: Swift 5, AppKit, an Xcode project, Swift packages
  (DGCharts only). It is a personal, non-commercial fork of Mos by Caldis (CC BY-NC 4.0;
  the attribution in `README.md` and the file headers stay).
- Names: the products are `Scrollio.app` (`com.nikklemenc.Scrollio`) and
  `Scrollio Debug.app` (`com.nikklemenc.Scrollio.debug`); the tests are
  `com.nikklemenc.ScrollioTests`. The project, folders, targets and Swift modules keep
  the old name: `Mos.xcodeproj`, `Mos/`, `MosTests/`, modules `Mos` (Release) and
  `Mos_Debug` (Debug, what tests import).
- Never rename persisted identifiers, even when they say "mos": UserDefaults keys, the
  `mosScroll*` action identifiers, shortcut identifiers, the JSON key `managedByMos`,
  Logi cache keys, CID and feature constants, storyboard object ids, string catalog keys.
- Deployment target: macOS 14.0 for every target. Do not write fallbacks for older
  systems. Gate only APIs newer than 14.0 (the existing `macOS 26` checks stay).
- There is no updater, no release process and no remote of our own. The git remote
  `upstream` is the original project: never push to it, never open issues or pull
  requests there.

## Commands

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme Debug -destination 'platform=macOS' test
xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/<TestClassName>
xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/<TestClassName>/<testMethodName>
xcodebuild -scheme Debug -configuration Release -destination 'platform=macOS' build
scripts/qa/lint-logi-boundary.sh
```

- Always use the shared scheme `Debug`. Never build with `-target Mos`.
- **Never pass `CODE_SIGNING_ALLOWED=NO`.** It re-signs `Scrollio Debug.app` ad hoc.
  The changed signature makes macOS ask for the Accessibility permission again, and if an
  instance with its global event tap is running, that modal prompt blocks the main thread
  and freezes all mouse and keyboard input. If it ever happened, rebuild normally to
  restore the signature.
- Keep the signing team and identities in the project as they are.
- To check that code compiles, prefer a plain `build`: it starts nothing and changes no
  signature.
- Before `test`, make sure no debug instance runs: `pgrep -fl "Scrollio Debug.app"` must
  print nothing. The tests run inside that app with its startup side effects off
  (`AppRuntime`): the app's event taps and Logitech sessions are not started, the real
  settings are not written and no login item is registered.

## Files and targets

- `Mos/` is a file-system-synchronized group: a file placed there is compiled, or copied
  into the app bundle, without a project edit. Put nothing there that should not ship.
- `MosTests/` is **not** synchronized: a new test file must be added to
  `Mos.xcodeproj/project.pbxproj` (file reference, group entry, build file, Sources
  phase of the `MosTests` target). A file that is only created is not compiled.
- After adding, moving or deleting Swift files, build or run the related tests.

## Module boundaries

See `.agents/docs/code-map.md` for the map. The rules:

- Logitech details (HID++ packets, device sessions, divert) stay inside `Mos/Logi/`.
  The rest of the app talks to `LogiCenter` and `Mos/Integration/` only.
  `scripts/qa/lint-logi-boundary.sh` enforces the allowlists and is run by
  `LogiBoundaryEnforcementTests`; run it after any change in `Mos/Logi/` or
  `Mos/Integration/`.
- `Mos/ScrollCore/`, input event handling and HID callbacks are hot paths: no avoidable
  allocations, no synchronous I/O, no heavy logging, no notifications, no UI or
  persistence work in them.
- Smooth scrolling has one path (`ScrollCore` -> `ScrollPoster`, see the code map). The
  scroll tap callback runs on the main thread, the display link on its own thread:
  `ScrollPoster` state is touched only under its lock, and only the main thread stops a
  session (`performRequestedStop`).
- Diagnostics go to the system log (`ScrollSystemLog`, category `scroll`; `LogiSystemLog`,
  category `logi`): state changes, decisions and one line per scroll, never a line per
  event, and no string built per event. Reading it: `README.md`, "Diagnostics".
- Nothing is written to a Logitech mouse unless "Let Scrollio manage this mouse"
  (`Options.shared.logiMouseManaged`) is on and the user set that value. Reading needs no
  switch.
- ButtonCore, InputEvent, Shortcut and Keys share one meaning of recording, display,
  persistence and execution. When you change one, check the others.

## Localization

- English is the only language. The mechanism stays: two string catalogs that must stay
  separate (`Mos/Localizable.xcstrings` for Swift, `Mos/mul.lproj/Main.xcstrings` for the
  storyboard).
- Every user-visible string is localized. In Swift use `NSLocalizedString(_:comment:)`,
  not `String(localized:)`.
- `PreferencesLocalizationTests` checks that the keys of the preferences panels exist,
  are not shown as raw keys and keep their format specifiers. Add the keys of new
  preferences strings to its list.
- Details and the steps for adding a language: `LOCALIZATION.md`.

## Verification

Choose by risk, and run it: reading the code is not verification.

| Change | Minimum | Also |
| --- | --- | --- |
| Docs, agent files | `git diff --check`, check paths and links | search for old paths |
| Swift logic | the related `MosTests` class | full test run |
| New, moved or deleted Swift file; project or target change | Debug build | related tests |
| ScrollCore hot path | `ScrollClassicPathTests`, `ScrollMotionTests`, `ScrollFilterTests`, `ScrollPoster*Tests`, `ScrollSystemLogTests` | full run; the owner scrolls by hand and reads the `scroll` log |
| ButtonCore, Shortcut, InputEvent | ButtonBinding, InputProcessor, ShortcutExecutor tests | the owner checks the Buttons pane |
| Logi, HID | the `MosTests/Logi*` tests and the boundary lint | real-device tests and the `logi` log, by the owner |
| Preferences panes | the pane's `Preferences*Tests` / `MousePreferencesTests`, `PreferencesWindowTests` | the owner looks at the pane; previews stop when it is hidden |
| UI text | catalogs in sync, `PreferencesLocalizationTests` | long text, dark mode |

- A bug fix gets a regression test that covers the old failure. If it cannot be automated,
  say why, what was checked by hand or by reading, and what the owner still has to confirm.
- Prefer testable shapes: pure logic, planners, packet builders, small injected seams and
  test doubles. Do not widen an API only for a test.
- A change to anything persisted needs a canary or migration test, or a clear statement
  of the risk. A retired setting's UserDefaults key goes into
  `ScrollSettingsCleanup.retiredDefaultsKeys` (removed on load) and is never reused.

## What needs the owner

Do these only when the owner asked for them explicitly:

- Anything with real hardware or the live system: real-device tests
  (`LOGI_REAL_DEVICE=1 xcodebuild -scheme Debug -testPlan DebugWithDevice -destination 'platform=macOS' test`,
  mouse connected), HID traffic, posting synthetic input events, launching the app while
  the owner's installed copy runs, anything that depends on the Accessibility permission.
- Changes to signing, entitlements or notarization.
- Changes to how existing settings are read, to persistence formats or to permission
  prompts.
- Pushing, publishing, or anything visible outside this machine.

This is not a checklist for ordinary tasks: mention it only when such an action is part
of the request.

## Reporting

Say why the change was made, what verification you actually ran, which relevant
verification you could not run, and the risks that remain. Nothing else.
