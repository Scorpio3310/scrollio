# Code map

A quick map for agents. It is not a design document: behaviour is defined by the sources
and the tests. Rules live in `AGENTS.md`.

## App (`Mos/`)

| Folder | What it does |
| --- | --- |
| `ScrollCore/` | Captures wheel events, filters and interpolates them, posts the smooth scroll (display link). Hot path. |
| `ButtonCore/` | Event tap for mouse buttons and keys; hands events to `InputProcessor`. |
| `InputEvent/` | The unified input event model, binding matching (`InputProcessor`), gesture navigation (recognizer, "follow the hand" session, pointer lock, dock swipe). |
| `Shortcut/` | System shortcut definitions and the executor of actions. |
| `Keys/` | Recording keys and mouse buttons: UI and data. |
| `Logi/` | Logitech HID++: device sessions, feature discovery, button divert, usage registry, wheel (SmartShift), basic mouse settings (`Basics/`: battery, pointer speed, haptic settings, press force), gesture raw XY and haptics, debug panel. |
| `Integration/` | The bridge between `Logi/` and the rest of the app. |
| `Options/` | Settings in UserDefaults, per-app rules, persistence models. |
| `Managers/` | App-level singletons: windows, the status item, the main menu. |
| `Components/` | Reusable UI, including Toast. |
| `Windows/` | Introduction (the Welcome Guide, built in code), Preferences and the Monitor window. |
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

## Persistence and compatibility

Be careful with these, and add a canary or compatibility test when you touch them:

- UserDefaults keys.
- Shortcut, action and category identifiers.
- Logi cache keys, feature and CID constants, usage registry constants.
- Storyboard object ids and string catalog keys.
- The first-launch copy of the settings of the original Mos (`Utils/LegacyMosTakeover.swift`).
