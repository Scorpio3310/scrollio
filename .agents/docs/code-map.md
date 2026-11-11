# Code map

A quick map for agents. It is not a design document: behaviour is defined by the sources
and the tests. Rules live in `AGENTS.md`.

## App (`Mos/`)

| Folder | What it does |
| --- | --- |
| `ScrollCore/` | Smooth scrolling, one path: `ScrollCore` takes the wheel event (tap callback, main thread) and adds max(Step, delta) × Speed to a target; `ScrollPoster` moves toward it on every display frame (CVDisplayLink thread, under its lock) with a lerp set by Duration (`ScrollMotion`, 60 Hz reference), a lead cap (`ScrollLeadLimiter`) and a soft start (`ScrollFilter`), and posts the frames in whole pixels, the fraction of each carried into the next (`ScrollPixelCarry`; frames slower than the dead zone, a speed in pixels per 60 Hz frame, are not posted); `ScrollPhase` adds the trackpad-style phases. `ScrollSystemLog` writes one system-log line per finished scroll and rate-limited passthrough reasons. Hot path. |
| `ButtonCore/` | Event tap for mouse buttons and keys; hands events to `InputProcessor`. |
| `InputEvent/` | The unified input event model, binding matching (`InputProcessor`), gesture navigation (recognizer, "follow the hand" session, pointer lock, dock swipe). |
| `Shortcut/` | System shortcut definitions and the executor of actions. |
| `Keys/` | Recording keys and mouse buttons: UI and data. `KeyRecorder` creates its event tap before it shows anything or diverts the Logitech buttons for recording. |
| `Logi/` | Logitech HID++: device sessions, feature discovery, button divert, usage registry, wheel (SmartShift; `LogiWheelController` writes only values the user set, never an unset one), gesture raw XY and haptic cues, the diagnostics panel ("Logitech Diagnostics"), `LogiSystemLog` (category `logi`). `LogiCenter` is the facade (also `controlRole(forMosCode:)` for the Buttons pane's drawing and `mouseDeviceStates()` with the battery). `Basics/`: battery (0x1004 / 0x1000), pointer speed (0x2201), haptic on/off and strength (0x19B0) and press force (0x19C0); one `LogiMouseBasicsController` per slot, one request at a time, byte layouts in the `*Protocol` files, public types in `LogiMouseBasicsTypes.swift`. |
| `MacPointer/` | The macOS pointer settings that apply to every mouse ("Tracking speed", "Pointer acceleration"), as System Settings › Mouse has them. `MacPointerSettings` is a set of read and write closures (`.system` in the app, `.inert` under XCTest); it writes only when the user moves the control in the Mouse pane: the HID event system property first, the global preference only if macOS took it. Scrollio stores nothing of its own here. |
| `Integration/` | The bridge between `Logi/` and the rest of the app: `LogiUsageBootstrap` pushes Options changes to `LogiCenter` (wheel, mouse basics with a 0.25 s settle, gesture tracking). |
| `Options/` | Settings in UserDefaults, per-app rules, persistence models. `Options.shared.logiMouse` holds the Logitech basics and `logiWheel` the wheel values (every value optional: nil leaves the mouse's value); `logiMouseManaged` is the one "Let Scrollio manage this mouse" switch (stored as `logiWheel.managedByMos`). `ScrollSettings.swift`: the five Feel presets, the slider ranges and the clean-up that runs on every load (`ScrollSettingsCleanup`, also removes the keys of retired settings). |
| `Managers/` | App-level singletons: windows, the main menu, the status item (`StatusItemManager`; what its menu lists is the pure `StatusMenu`, rebuilt each time it opens: battery lines, Pause / Resume, Settings, the diagnostics with Option, Quit), `AppRunController` (the one path that starts and stops the event taps and the Logitech sessions: launch, sleep and wake, fast user switching, lost Accessibility access, "Pause Scrollio" (never stored), quit; taps first, Logitech only when every tap runs) and `BatteryWatcher` (one toast at low, one at critical, from what `LogiCenter` reports). |
| `Components/` | Toast, and `BrandTag` (the "Logi" tag of Logitech buttons in the key preview and the scroll keys). |
| `Windows/` | Introduction (the Welcome Guide, built in code), Preferences and the Monitor window. The Preferences window is a sidebar of panes, as in System Settings (`PreferencesSplitViewController` with `PreferencesSidebarViewController` and `PreferencesPaneHostViewController`; the pane list is `PreferencesPane.all`; `selectPane(withIdentifier:)` opens a pane); each pane sits in a 520 pt column (`PreferencesWindowLayout`), centred when narrower, and scrolls when taller than the window. Every pane is built in code (the storyboard scenes of General, Scrolling, Buttons and Apps are shells) on `PreferencesGroupedForm` (rows in rounded boxes with switch, slider and disclosure rows and slider tick marks, muted notes under the boxes, as in System Settings) and its `PreferencesListBox` (a box of selectable rows with + and − under them, as in Login Items); `PreferencesForm` keeps the window background, the column width and `fitToContent`. Buttons: a card with a drawing of the mouse (`ButtonsHeaderView`) over the list of bindings, each row with a small picture of where its button is (`ButtonsMouseMiniature`, from `ButtonTriggerPicture`: a part lit only where the place is certain, else the button's number), plain names from `ButtonTriggerNaming`, Undo for a removal. Apps: the list and a page per app (`ApplicationDetailViewController`, with the Scrolling pane embedded in per-app mode). General: a card with the app icon, name and version (`GeneralHeaderView`, in the look of the Mouse card; there is no About pane, "About Scrollio" opens General and a remembered "about" opens it too), "Scrollio is paused" with Resume (only while paused), open at login (with the approval row), show in menu bar, the Accessibility status, then the Welcome Guide and the credit line the licence asks for (the developer tools are in the status-bar menu, with Option, not in a pane). Scrolling and Gestures have an animated preview (`ScrollPreviewView`, `GesturePreviewView`: a display link that runs only while the pane is shown and Reduce Motion is off; the pictures are in the `*Artwork` files, the timelines in the pure `*Motion` files). The mouse drawings are in `MouseView/MouseArtwork.swift`: one per model (MX Master 4 with its three side buttons and the thumb panel, MX Master 3 / 3S, a generic mouse), chosen from the connected mouse's name by `MouseArtworkModel.model(forDeviceName:)` and shared by the Mouse, Buttons and Gestures panes. `PreferencesSlider` sends nothing for a press that does not move its knob, or while it is off. |
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
