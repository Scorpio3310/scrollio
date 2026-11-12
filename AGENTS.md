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

- Scrollio is a macOS menu-bar app: Swift 5, AppKit, an Xcode project, one Swift package
  (DGCharts). It is a non-commercial fork of Mos by Caldis (CC BY-NC 4.0). The attribution
  stays wherever it is: the notices at the top of `LICENSE`, "Licence and credits" in
  `README.md`, `NSHumanReadableCopyright` in `Scrollio/Info.plist`, the credit line in
  General, the file headers. `Scrollio/Acknowledgements.txt` ships inside the app and on
  the disk image and carries the same list of projects as the README: change both
  (`ReleaseReadinessTests` compares them).
- DGCharts is for the debug build only: it draws the Scroll Monitor
  (`Scrollio/Windows/MonitorWindow/`, every file inside `#if DEBUG`). The Release
  configuration of the app target leaves the package out of the link and of the bundle
  (`EXCLUDED_SOURCE_FILE_NAMES = DGCharts*`), so an `import DGCharts` outside `#if DEBUG`
  does not link in Release, and `scripts/release.sh` refuses an app that contains it.
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
  and published by the owner, from a commit that carries the tag `v<version>` (`v1.0.0`);
  the version of a release is its tag's. Never create, move, delete or push a tag unless
  the owner asked for exactly that, and never `git push --tags`: a clone can also hold
  the original project's tags (`1.0`, `1.0.0` … without a `v`), which must not reach
  Scrollio's repository. The original project (<https://github.com/Caldis/Mos>) is a
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
  What it checks and what it leaves behind: `README.md`, "Making a release". A check in
  either script never pipes a tool into `grep -q` (under `pipefail` a match then reads as
  no match): the output goes to a variable or a file first.
- Install the release app with `scripts/install.sh`, not by copying a build by hand: it
  refuses a build whose signature differs from the installed app's (see the next point),
  one that carries `get-task-allow`, and one instrumented for code coverage (the test
  plans keep `codeCoverage` off for that reason).
- **Never pass `CODE_SIGNING_ALLOWED=NO`.** It re-signs `Scrollio Debug.app` ad hoc.
  The changed signature makes macOS ask for the Accessibility permission again, and if an
  instance with its global event tap is running, that modal prompt blocks the main thread
  and freezes all mouse and keyboard input. If it ever happened, rebuild normally to
  restore the signature.
- Keep the signing team and identities in the project as they are. Another Mac's team
  goes into `Local.xcconfig` (ignored by git; template `Local.xcconfig.example`), which
  `scripts/install.sh` passes to its build and a plain build takes with
  `-xcconfig Local.xcconfig` (`README.md`, "Build from source").
- To check that code compiles, prefer a plain `build`: it starts nothing and changes no
  signature.
- Before `test`, make sure no debug instance runs: `pgrep -fl "Scrollio Debug.app"` must
  print nothing. The tests run inside that app with its startup side effects off
  (`AppRuntime`): the app's event taps and Logitech sessions are not started, the real
  settings are not written and no login item is registered.
- The suite passes with no display awake (a night run, a headless Mac): a test that needs
  a display link skips and says so. Each test has 60 seconds (the test plans' time limit),
  and the order is shuffled at every run: a test must not lean on the one before it.
- Render tests draw panes and the Welcome Guide to PNG files and run only when asked to:
  `TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:ScrollioTests/<Class>`.
  xcodebuild hands a variable to the tests only when its name begins with `TEST_RUNNER_`
  (the tests see it without the prefix); a variable set in the shell without it does not
  arrive.

## Files and targets

- `Scrollio/` is a file-system-synchronized group: a file placed there is compiled, or
  copied into the app bundle, without a project edit. Put nothing there that should not
  ship. (`Scrollio/Acknowledgements.txt` is there because it should.)
- `ScrollioTests/` is **not** synchronized: a new test file must be added to
  `Scrollio.xcodeproj/project.pbxproj` (file reference, group entry, build file, Sources
  phase of the `ScrollioTests` target). A file that is only created is not compiled.
- After adding, moving or deleting Swift files, build or run the related tests.
- Outside the targets: `scripts/` (`install.sh`, `release.sh` and the boundary lint),
  `tools/` (hand-run HID++ probes and a toast harness; read `tools/README.md` before
  running a probe), `assets/readme/` (the README's pictures, made by the render tests),
  and the documents a visitor reads first: `README.md`, `LICENSE`, `SECURITY.md`,
  `CONTRIBUTING.md`. They describe the app as it is: a change that makes one of their
  sentences untrue changes the sentence too.

## Module boundaries

See `.agents/docs/code-map.md` for the map. The rules:

- Logitech details (HID++ packets, device sessions, divert) stay inside `Scrollio/Logi/`.
  The rest of the app talks to `LogiCenter` and `Scrollio/Integration/` only.
  `scripts/qa/lint-logi-boundary.sh` enforces the allowlists and is run by
  `LogiBoundaryEnforcementTests`; run it after any change in `Scrollio/Logi/` or
  `Scrollio/Integration/`. It knows a Logitech type by its `Logi` prefix: give a new
  top-level type in `Scrollio/Logi/` that prefix, or add its name to `LOGI_SYMBOL` in the
  lint.
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
  changes, decisions and one line per scroll (or per roll of the thumb wheel, or per hold
  of a gesture button the mouse tracks), never a line per wheel, pointer or key event, and
  no string built per event. Nothing a user types, and no path of a user's file, goes
  into a log. Use these, not `NSLog`: only they write to the app's subsystem.
  Reading it: `README.md`, "Diagnostics".
- A write to a Logitech device never runs on the main thread: `IOHIDDeviceSetReport` takes
  15 to 29 ms over Bluetooth and the main thread serves every event tap. Send through the
  session (`LogiReportWriter`: one serial queue per device, order kept); never call
  `IOHIDDeviceSetReport` directly.
- No setting is written to a Logitech mouse unless "Let Scrollio manage this mouse"
  (`Options.shared.logiMouseManaged`) is on, the user set that value and the value
  freshly read from the mouse differs. Apart from settings: a button is diverted for a
  binding and while a button is recorded, and given back when Scrollio pauses or quits; a
  Logitech button action writes when its button is pressed; a gesture cue plays a pulse
  and may switch the haptics on. Reading needs no switch. The header of
  `LogiDeviceSession` has the whole list; the Logitech Diagnostics window writes in debug
  builds only. A new kind of write needs a line in that header and in `README.md`,
  "Logitech MX mice".
- ButtonCore, InputEvent, Shortcut and Keys share one meaning of recording, display,
  persistence and execution. When you change one, check the others.
- Only `AppRunController` (`Scrollio/Managers/`) starts and stops the cores (the scroll
  and button event taps and the Logitech sessions): launch, sleep and wake, fast user
  switching, lost Accessibility access, "Pause Scrollio", quit. An active event tap that
  is not serviced freezes input system-wide: never leave one installed while the cores
  count as stopped, and never block the main thread while one runs. The pointer-movement
  tap of gesture holds is made on demand while the cores run; their stop releases it.
  ButtonCore's keys tap too: it exists only while a key is bound, a button holds a
  modifier or a key-started action is held.

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
| `scripts/`, licence and notices, `Acknowledgements.txt`, the DGCharts exclusion | `ReleaseReadinessTests`, `bash -n` on the script, `scripts/install.sh --check` | a Release build; `scripts/release.sh --check` when the owner asked (it signs with the Developer ID) |

- A bug fix gets a regression test that covers the old failure. If it cannot be automated,
  say why, what was checked by hand or by reading, and what still has to be confirmed by
  hand.
- Prefer testable shapes: pure logic, planners, packet builders, small injected seams and
  test doubles. Do not widen an API only for a test.
- Under XCTest every real effect is inert unless a test asks for it: posting an event, an
  event tap, the pointer, a toast, opening an app or a file, the app's real preferences.
  New code that reaches out of the process gets a seam whose default does nothing while
  `AppRuntime.isRunningXCTest` (as `ShortcutExecutor.post`), so a test that forgets to
  replace it does nothing to the Mac it runs on; `TestIsolationTests` lists the files
  that may hold such a call.
- A test that stores settings takes its store from `TestDefaults` (a temporary folder,
  removed with the test) and hands it to `Options.defaults` or the pane's own seam. Never
  `UserDefaults(suiteName:)` with a name (it leaves a file in `~/Library/Preferences`
  for every test) and never `UserDefaults.standard`.
- A change to anything persisted needs a canary or migration test, or a clear statement
  of the risk. A retired setting's UserDefaults key goes into
  `ScrollSettingsCleanup.retiredDefaultsKeys` (removed on load) and is never reused.

## What needs the user's go-ahead

Do these only when the user asked for them explicitly:

- Anything with real hardware or the live system: real-device tests
  (`xcodebuild -scheme Debug -testPlan DebugWithDevice -destination 'platform=macOS' test`,
  mouse connected; the plan itself tells the tests that a mouse is there), HID traffic (the probes in `tools/hidpp/` among it), posting synthetic
  input events, launching the app while an installed copy runs, anything that depends on
  the Accessibility permission.
- Changes to signing, entitlements or notarization. Creating, moving, deleting or pushing
  a tag.
- Changes to how existing settings are read, to persistence formats or to permission
  prompts.
- Pushing, publishing, or anything visible outside this machine.

This is not a checklist for ordinary tasks: mention it only when such an action is part
of the request.

## Reporting

Say why the change was made, what verification you actually ran, which relevant
verification you could not run, and the risks that remain. Nothing else.
