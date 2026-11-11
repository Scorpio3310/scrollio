# Code map

A quick map for agents. It is not a design document: behaviour is defined by the sources
and the tests. Rules live in `AGENTS.md`.

## App (`Mos/`)

| Folder | What it does |
| --- | --- |
| `ScrollCore/` | Smooth scrolling, one path: `ScrollCore` takes the wheel event (tap callback, main thread) and adds max(Step, delta) × Speed to a target; `ScrollPoster` moves toward it on every display frame (CVDisplayLink thread, under its lock) with a lerp set by Duration (`ScrollMotion`, 60 Hz reference), a lead cap (`ScrollLeadLimiter`) and a soft start (`ScrollFilter`), and posts the frames; `ScrollPhase` adds the trackpad-style phases. `ScrollSystemLog` writes one system-log line per finished scroll and rate-limited passthrough reasons. Hot path. |
| `ButtonCore/` | Event tap for mouse buttons and keys; hands events to `InputProcessor`. |
| `InputEvent/` | The unified input event model, binding matching (`InputProcessor`), gesture navigation (recognizer, "follow the hand" session, pointer lock, dock swipe). |
| `Shortcut/` | System shortcut definitions and the executor of actions. |
| `Keys/` | Recording keys and mouse buttons: UI and data. |
| `Logi/` | Logitech HID++: device sessions, feature discovery, button divert, usage registry, wheel (SmartShift), gesture raw XY and haptic cues, debug panel, `LogiSystemLog` (category `logi`). `Basics/`: battery (0x1004 / 0x1000), pointer speed (0x2201), haptic on/off and strength (0x19B0) and press force (0x19C0); one `LogiMouseBasicsController` per slot, one request at a time, byte layouts in the `*Protocol` files, public types in `LogiMouseBasicsTypes.swift`. |
| `Integration/` | The bridge between `Logi/` and the rest of the app: `LogiUsageBootstrap` pushes Options changes to `LogiCenter` (wheel, mouse basics with a 0.25 s settle, gesture tracking). |
| `Options/` | Settings in UserDefaults, per-app rules, persistence models. `Options.shared.logiMouse` holds the Logitech basics (every field optional: nil leaves the mouse's value); `logiMouseManaged` is the one "Let Scrollio manage this mouse" switch (stored as `logiWheel.managedByMos`). `ScrollSettings.swift`: the five Feel presets, the slider ranges and the clean-up that runs on every load (`ScrollSettingsCleanup`, also removes the keys of retired settings). |
| `Managers/` | App-level singletons: windows, the status item, the main menu. |
| `Components/` | Reusable UI, including Toast. |
| `Windows/` | Introduction (the Welcome Guide, built in code), Preferences and the Monitor window. The Preferences window is a sidebar of panes, as in System Settings (`PreferencesSplitViewController` with `PreferencesSidebarViewController` and `PreferencesPaneHostViewController`; the pane list is `PreferencesPane.all`; `selectPane(withIdentifier:)` opens a pane); each pane sits in a 520 pt column (`PreferencesWindowLayout`), centred when narrower, and scrolls when taller than the window. Panes built in code use `PreferencesForm` (the label-column grid of the storyboard panes) or `PreferencesGroupedForm` (rows in rounded boxes with switch, slider and disclosure rows and slider tick marks, as in System Settings). Scrolling, Mouse and Gestures are built on the grouped form; Scrolling and Gestures have an animated preview (`ScrollPreviewView`, `GesturePreviewView`: a display link that runs only while the pane is shown and Reduce Motion is off; the pictures are in the `*Artwork` files, the timelines in the pure `*Motion` files). |
| `Utils/` | Event tap wrapper (`Interceptor`), constants, the login item, the takeover from Mos, helpers. |
| `Extension/` | Extensions of system types. |

Tests are in `MosTests/`; Logitech test doubles in `MosTests/LogiTestDoubles/`.

## Around the app

- `scripts/qa/lint-logi-boundary.sh`: the Logi boundary lint (also run by a test).
- `tools/`: hand-run HID++ probes and a standalone regression harness. Not part of any target.
- `assets/`: images for the README and source artwork. Run-time images belong in
  `Mos/Assets.xcassets`.
- `docs/`: design notes and plans, mostly from the original project. History only.

## Boundaries

- ScrollCore is the scroll hot path: performance comes first there.
- ButtonCore, InputEvent, Shortcut and Keys together handle recording, menus, persistence
  and execution of bindings; keep their meaning of an event and an action the same.
- Logitech details stay in `Mos/Logi/`. Other layers use `LogiCenter`, `Mos/Integration/`
  or an explicit facade. `Mos/Integration/` may know more bridge types; the rest of the
  app only the public allowlist in `scripts/qa/lint-logi-boundary.sh`.
- Real-device logic is isolated behind `LOGI_REAL_DEVICE=1`.
- Nothing is written to a Logitech mouse while `logiMouseManaged` is off (gesture cues may
  still switch its haptics on, unless the user switched haptics off in the Mouse pane).

## Diagnostics

The system log, subsystem `com.nikklemenc.Scrollio` (`.debug` for the debug build):
category `scroll` (`ScrollSystemLog`) and category `logi` (`LogiSystemLog`). How to read
it: `README.md`, "Diagnostics". Both are low volume by rule: state changes, decisions and
one line per scroll, never a line per event.

## Persistence and compatibility

Be careful with these, and add a canary or compatibility test when you touch them:

- UserDefaults keys.
- Shortcut, action and category identifiers.
- Logi cache keys, feature and CID constants, usage registry constants.
- Storyboard object ids and string catalog keys.
- The first-launch copy of the settings of the original Mos (`Utils/LegacyMosTakeover.swift`).
