# AGENTS.md

The single guidance file for coding agents (and people) working in this repository.
Tool-specific entry files (`CLAUDE.md`) only point here; do not keep a second copy of
these rules anywhere.

## Priority

1. The user's current request and the system or tool safety rules.
2. This file.
3. `.agents/docs/code-map.md`.
4. The current sources, the Xcode project and the test plans.

## Before you start

1. Read this file, then only the sources, tests and docs the task needs.
2. Run `git status --short` and keep changes that are already there.

## The project

- Scrollio is a macOS menu-bar app: Swift 5, AppKit, an Xcode project, Swift packages
  (DGCharts only). It is a non-commercial fork of Mos by Caldis (CC BY-NC 4.0; the
  attribution in `README.md` and the file headers stay).
- Names: the products are `Scrollio.app` (`com.nikklemenc.Scrollio`) and
  `Scrollio Debug.app` (`com.nikklemenc.Scrollio.debug`); the tests are
  `com.nikklemenc.ScrollioTests`. The project, folders and targets carry the same name:
  `Scrollio.xcodeproj`, `Scrollio/`, `ScrollioTests/`, targets `Scrollio` and
  `ScrollioTests`; the Swift modules are `Scrollio` (Release), `Scrollio_Debug` (Debug,
  what tests import) and `ScrollioTests`.
- "Mos" is the original app, never this one. The word stays only where it means that app
  or its authors: the credit and the licence, the header blocks at the top of the source
  files, comments in Chinese (the original authors'), and `LegacyAppQuitter`, which asks
  a running Mos to quit (`com.caldis.Mos`). Do not use it for anything of Scrollio's.
- Never rename persisted identifiers: UserDefaults keys, action identifiers (`scrollDash`,
  `scrollToggle` and `scrollBlock` among them), shortcut identifiers, JSON keys (such as
  `managedByScrollio`), Logi cache keys, CID and feature constants, storyboard object
  ids, string catalog keys. The stored names that carried the original app's name were
  renamed once, together with the project and before the first public release, on the
  owner's decision and without a migration: the old names are not read. That is not a
  precedent.
- Deployment target: macOS 14.0 for every target. Do not write fallbacks for older
  systems. Gate only APIs newer than 14.0 (the existing `macOS 26` checks stay).
- There is no updater. A release is made by hand with `scripts/release.sh` (see Commands)
  and published by the owner. The original project (<https://github.com/Caldis/Mos>) is a
  separate repository: never push to it, and never open issues or pull requests there
  about Scrollio.

## Commands

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme Debug -destination 'platform=macOS' test
xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:ScrollioTests/<TestClassName>
xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:ScrollioTests/<TestClassName>/<testMethodName>
xcodebuild -scheme Debug -configuration Release -destination 'platform=macOS' build
scripts/qa/lint-logi-boundary.sh
scripts/install.sh --check     # release build + signature, entitlement and binary checks
scripts/install.sh             # the same, then install to /Applications and start it
scripts/release.sh --check     # universal build signed with Developer ID + checks; nothing is notarized
scripts/release.sh             # the same, then notarized by Apple and packed into build/release/Scrollio-<version>.dmg
```

- Always use the shared scheme `Debug`. Never build with `-target Scrollio`.
- `scripts/release.sh` builds the app for other people's Macs. It passes the Developer ID
  identity to that one build and leaves the project's signing settings alone. Without
  `--check` it uploads the build to Apple's notary service: run it only when the owner
  asked for a release. It never installs: its signature is not the development signature
  of the copy in `/Applications`, so that copy would be asked for Accessibility again.
- Install the release app with `scripts/install.sh`, not by copying a build by hand: it
  refuses a build whose signature differs from the installed app's (see the next point),
  one that carries `get-task-allow`, and one instrumented for code coverage (the test
  plans keep `codeCoverage` off for that reason).
- **Never pass `CODE_SIGNING_ALLOWED=NO`.** It re-signs `Scrollio Debug.app` ad hoc.
  The changed signature makes macOS ask for the Accessibility permission again, and if an
  instance with its global event tap is running, that modal prompt blocks the main thread
  and freezes all mouse and keyboard input. If it ever happened, rebuild normally to
  restore the signature.
- Keep the signing team and identities in the project as they are. To build on another
  Mac, set your own team locally and do not commit it (`README.md`, "Build from source").
- To check that code compiles, prefer a plain `build`: it starts nothing and changes no
  signature.
- Before `test`, make sure no debug instance runs: `pgrep -fl "Scrollio Debug.app"` must
  print nothing. The tests run inside that app with its startup side effects off
  (`AppRuntime`): the app's event taps and Logitech sessions are not started, the real
  settings are not written and no login item is registered.

## Files and targets

- `Scrollio/` is a file-system-synchronized group: a file placed there is compiled, or
  copied into the app bundle, without a project edit. Put nothing there that should not
  ship.
- `ScrollioTests/` is **not** synchronized: a new test file must be added to
  `Scrollio.xcodeproj/project.pbxproj` (file reference, group entry, build file, Sources
  phase of the `ScrollioTests` target). A file that is only created is not compiled.
- After adding, moving or deleting Swift files, build or run the related tests.
- Outside the targets: `scripts/` (the install script and the boundary lint), `tools/`
  (hand-run HID++ probes and a toast harness; read `tools/README.md` before running a
  probe), `assets/readme/` (the README's pictures, made by the render tests).

## Module boundaries

See `.agents/docs/code-map.md` for the map. The rules:

- Logitech details (HID++ packets, device sessions, divert) stay inside `Scrollio/Logi/`.
  The rest of the app talks to `LogiCenter` and `Scrollio/Integration/` only.
  `scripts/qa/lint-logi-boundary.sh` enforces the allowlists and is run by
  `LogiBoundaryEnforcementTests`; run it after any change in `Scrollio/Logi/` or
  `Scrollio/Integration/`.
- `Scrollio/ScrollCore/`, input event handling and HID callbacks are hot paths: no
  avoidable allocations, no synchronous I/O, no heavy logging, no notifications, no UI or
  persistence work in them.
- Smooth scrolling has one path (`ScrollCore` -> `ScrollPoster`, see the code map). The
  scroll tap callback runs on the main thread, the display link on its own thread:
  `ScrollPoster` state is touched only under its lock, and only the main thread stops a
  session (`performRequestedStop`).
- Diagnostics go to the system log (`ScrollSystemLog`, category `scroll`; `LogiSystemLog`,
  category `logi`; `AppSystemLog`, category `app`: the app's own health: starts and stops,
  event taps that macOS turned off or that could not be created, recoveries): state
  changes, decisions and one line per scroll, never a line per event, and no string built
  per event. Use these, not `NSLog`: only they write to the app's subsystem.
  Reading it: `README.md`, "Diagnostics".
- A write to a Logitech device never runs on the main thread: `IOHIDDeviceSetReport` takes
  15 to 29 ms over Bluetooth and the main thread serves every event tap. Send through the
  session (`LogiReportWriter`: one serial queue per device, order kept); never call
  `IOHIDDeviceSetReport` directly.
- Nothing is written to a Logitech mouse unless "Let Scrollio manage this mouse"
  (`Options.shared.logiMouseManaged`) is on and the user set that value. Reading needs no
  switch.
- ButtonCore, InputEvent, Shortcut and Keys share one meaning of recording, display,
  persistence and execution. When you change one, check the others.
- Only `AppRunController` (`Scrollio/Managers/`) starts and stops the cores (the scroll
  and button event taps and the Logitech sessions): launch, sleep and wake, fast user
  switching, lost Accessibility access, "Pause Scrollio", quit. An active event tap that
  is not serviced freezes input system-wide: never leave one installed while the cores
  count as stopped, and never block the main thread while one runs. The pointer-movement
  tap of gesture holds is made on demand while the cores run; their stop releases it.

## Strings

English is the only language. The localization mechanism stays, with two string catalogs
that must stay separate:

| File | Strings | Keys |
| --- | --- | --- |
| `Scrollio/Localizable.xcstrings` | Used from Swift with `NSLocalizedString` | Readable phrases (older keys) or identifiers: those of `SystemShortcut.Shortcut`, and by area `general-*`, `scrolling-*`, `buttons-*`, `mouse-*`, `gesture-*` / `gestures-*`, `apps-*`, `about-*`, `preferences-*`, `main-menu-*`, `status-menu-*` / `status-item-*`, `intro-*`, `toast-*` |
| `Scrollio/mul.lproj/Main.xcstrings` | The storyboard (`Scrollio/Base.lproj/Main.storyboard`) | Interface Builder object ids (`AYu-sK-qS6.title`) |

- Every user-visible string is localized. In Swift use `NSLocalizedString(_:comment:)`,
  not `String(localized:)`. A new key goes into `Localizable.xcstrings` with its English
  value (a build in Xcode extracts new keys).
- Never rename a key that code, saved settings or Interface Builder uses, and never edit
  an object id by hand. A `SystemShortcut.Shortcut`'s `identifier` is its key: menus and
  the Buttons pane show `NSLocalizedString(identifier, …)`.
- The English values in `Main.xcstrings` override the storyboard's text: a storyboard
  title is changed in both places. When a storyboard element is deleted, remove its
  entries.
- `Localizable.xcstrings` stays byte-stable: a script that edits it writes
  `json.dumps(obj, ensure_ascii=False, indent=2, separators=(",", ": ")) + "\n"`.
  `Main.xcstrings` is in Xcode's own format (`"key" : value`): edit it in Xcode, or keep
  that format.
- Keep the modifier symbols ("⌘ Command", "⌥ Option", "⌃ Control", "⇧ Shift") and the
  product names (Scrollio, SmartShift, Logi Options+, MX Master, HID++, Mission Control)
  as they are.
- `PreferencesLocalizationTests` checks, for each locale in `locales` (`["en"]`), that
  the keys of the preference panes, the sidebar, the menus and the Welcome Guide exist,
  are not empty and are not shown as raw keys (one array per area: `generalKeys`,
  `scrollingKeys`, `buttonsKeys`, `gesturesKeys`, `mouseKeys`, `appsKeys`, `windowKeys`,
  `menuKeys`, `introKeys`), and that each string formatted with `String(format:)` takes
  the arguments its call site passes (`formatArguments`). Add a new key to the array of
  its area, and a formatted one to `formatArguments` too: several keys are built from
  variables, and a missing one would only show up as the raw key in the UI.
- Adding a language: add it to `knownRegions` in the project for both catalogs, translate
  both catalogs (the terms of System Settings for system features), add the locale to
  `PreferencesLocalizationTests.locales`, and look for clipped text in the Welcome Guide,
  every pane, the button recorder and the action menus.

## Verification

Choose by risk, and run it: reading the code is not verification.

| Change | Minimum | Also |
| --- | --- | --- |
| Docs, agent files | `git diff --check`, check paths and links | search for old paths |
| Swift logic | the related `ScrollioTests` class | full test run |
| New, moved or deleted Swift file; project or target change | Debug build | related tests |
| ScrollCore hot path | `ScrollClassicPathTests`, `ScrollMotionTests`, `ScrollFilterTests`, `ScrollPoster*Tests`, `ScrollSystemLogTests` | full run; by hand: scroll and read the `scroll` log |
| ButtonCore, Shortcut, InputEvent | ButtonBinding, InputProcessor, ShortcutExecutor tests | by hand: the Buttons pane |
| App lifecycle (`AppRunController`, `AppDelegate`, status-bar menu) | `AppRunControllerTests`, `StatusMenuTests` | by hand: sleep and wake, another user, Pause / Resume, Accessibility turned off and on |
| Logi, HID | the `ScrollioTests/Logi*` tests and the boundary lint | real-device tests and the `logi` log, by hand |
| Preferences panes | the pane's `Preferences*Tests` / `MousePreferencesTests`, `PreferencesWindowTests` | by hand: look at the pane (its render test can draw it); previews stop when it is hidden |
| UI text | catalogs in sync, `PreferencesLocalizationTests` | long text, dark mode |

- A bug fix gets a regression test that covers the old failure. If it cannot be automated,
  say why, what was checked by hand or by reading, and what still has to be confirmed by
  hand.
- Prefer testable shapes: pure logic, planners, packet builders, small injected seams and
  test doubles. Do not widen an API only for a test.
- A change to anything persisted needs a canary or migration test, or a clear statement
  of the risk. A retired setting's UserDefaults key goes into
  `ScrollSettingsCleanup.retiredDefaultsKeys` (removed on load) and is never reused.

## What needs the user's go-ahead

Do these only when the user asked for them explicitly:

- Anything with real hardware or the live system: real-device tests
  (`LOGI_REAL_DEVICE=1 xcodebuild -scheme Debug -testPlan DebugWithDevice -destination 'platform=macOS' test`,
  mouse connected), HID traffic (the probes in `tools/hidpp/` among it), posting synthetic
  input events, launching the app while an installed copy runs, anything that depends on
  the Accessibility permission.
- Changes to signing, entitlements or notarization.
- Changes to how existing settings are read, to persistence formats or to permission
  prompts.
- Pushing, publishing, or anything visible outside this machine.

This is not a checklist for ordinary tasks: mention it only when such an action is part
of the request.

## Reporting

Say why the change was made, what verification you actually ran, which relevant
verification you could not run, and the risks that remain. Nothing else.
