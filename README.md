# Scrollio

Scrollio is a macOS menu-bar utility for people who use a mouse. It makes the scroll
wheel as smooth as a trackpad, lets every mouse button run an action, and adds
gestures and wheel settings for Logitech mice.

It is a personal, non-commercial fork of [Mos](https://github.com/Caldis/Mos) by Caldis.
See [Attribution and licence](#attribution-and-licence).

- macOS 14.0 or later
- Swift 5, AppKit, an Xcode project with Swift packages
- No updater and no telemetry; the app makes no network requests

## Features at a glance

**Scrolling**

- Smooth scrolling: every click of the wheel becomes an even movement that glides out,
  the way a trackpad scrolls. Two things shape it: how long the page keeps gliding after
  the wheel stops (five feels from Direct to Float, or an exact glide time under
  Advanced), and how far one click moves it. An animated preview in the Scrolling pane
  shows the feel before you scroll.
- Reverse the wheel direction.
- Trackpad-style scroll events (gesture phases), so apps bounce at the top and bottom.
- Scroll keys: hold a key or button to scroll faster, scroll sideways, or pause
  smoothing (for exact steps, for example when zooming with ⌘ and the wheel).
- Per-app scrolling (the Apps pane): an app can use the Scrolling settings or keep its
  own, on a page of its own. "Limit scrolling to these apps" makes the apps not listed
  scroll the way macOS does; buttons and gestures still work in every app.
- With several displays, the motion is timed to the display the pointer is on.

**Buttons**

- Bind any mouse button or key to an action: system shortcuts (Mission Control, Spaces,
  screenshots and more), custom key combinations, mouse buttons, the scroll keys, Gesture
  Navigation, or opening an app, file or script.
- A drawing of the mouse lights the button a row is about; a row says when its button is
  also a scroll key or another app (Logi Options+) may take it over.
- Removing a button or an app can be undone (Edit > Undo).

**Gestures**

- Hold a button and move the mouse: one action per direction, plus a click action.
- "Follow the hand" mode drives the Spaces swipe directly, like a trackpad.
- The pointer can stay frozen while the button is held.

**Logitech mice (HID++, over Bolt or Unifying receivers and Bluetooth)**

- Buttons that macOS does not report (gesture button, mode-shift button and others)
  become bindable.
- The Mouse pane shows the battery and, on mice that support them, pointer speed (DPI),
  haptic feedback and its strength, the thumb panel's press force, scroll-wheel mode
  (SmartShift, ratchet, free-spin), SmartShift sensitivity and wheel force.
- Nothing is written to a mouse until "Let Scrollio manage this mouse" is on. Then only
  the values you set are written, only when the mouse reports something else, and again
  after each reconnect. With several mice connected, your choices go to all of them.
- Movement tracked by the mouse itself during a gesture, and haptic feedback on mice
  that have it.
- A low-battery warning: one toast when a mouse reaches 10 % and one more at 5 %,
  again only after it was charged.
- Logitech Diagnostics, a window with the HID++ details of connected mice: hold Option
  and open the menu-bar menu. In the release app it only reads; it sends nothing that
  changes a mouse.

**App**

- Lives in the menu bar. Its menu shows each Logitech mouse's battery, "Pause Scrollio" /
  "Resume Scrollio" (a pause stops the event handling and gives the Logitech mice their
  buttons back; it is not remembered, a relaunch runs again), Settings and Quit. With
  Option held it also lists Logitech Diagnostics (the debug build also Scroll Monitor and
  Test Toasts). The icon is dimmed while Scrollio is paused, waits for the Accessibility
  access, or could not start its event taps and tries again (its tooltip says which).
  While paused, General also says so, with a Resume button (the way back when the menu
  bar icon is hidden).
- The menu bar icon can be hidden (General > Show in menu bar); opening the app again
  then shows the settings, or the Welcome Guide while the access is missing.
- Can open at login; General says when macOS waits for that to be approved in System
  Settings, and whether the Accessibility access is allowed.
- Settings in one window with a sidebar of panes, as in System Settings.
- Stops while the Mac sleeps or another user has it, and starts again when this user is
  back.
- It quits a running Mos at launch and, on the first launch, copies its settings. Another
  running copy of Scrollio is asked to quit too, and waited for (at most 3 seconds, then
  forced) before this one starts its event taps and Logitech sessions.

## Diagnostics

Scrollio writes what it really did to the system log, so behaviour can be checked on the
machine it runs on instead of guessed at:

```bash
# the last ten minutes
log show --last 10m --predicate 'subsystem == "com.nikklemenc.Scrollio"'
# live, one category
log stream --predicate 'subsystem == "com.nikklemenc.Scrollio" AND category == "scroll"'
```

The debug build logs under `com.nikklemenc.Scrollio.debug`. Nothing is logged per event.

- Category `scroll`, one line per finished scroll:

  ```text
  scroll: 5 wheel events 2140 px in -> 61 frames 2112 px out (largest 98.4), wheel 44 ms,
  glide after the last event 820 ms, Duration 4.50 (tau 230 ms), trackpad-style off, ended MomentumEnd
  ```

  The distance in is what the wheel asked for (Step and Speed applied); the distance out is
  what was posted, short of it only by the tail under the dead zone (frames go out in whole
  pixels, the fraction of each carried into the next, so the same on any display rate).
  Duration is the one that scroll used: the global one or the app's own. With trackpad-style
  events the line says in which form the scroll went out. `on (long touch: 1 touches)`: one
  touch for as long as the wheel turned, for apps whose scroll views follow the touch only and
  compute the glide themselves (AppKit and UIKit: Finder, Settings, most apps).
  `on (flick: 1 touches, 4 wheel events into a glide)`: a short touch and its glide, so that a
  page edge bounces as after a trackpad flick, for apps that scroll by the glide's events (the
  Chromium engine: Chrome, Dia, Arc, Electron apps); it says how many touches ("began") the
  app got and how many wheel events went on with a glide instead of beginning a touch.
- Category `scroll`, at most one line per reason every 3 seconds while wheel events are
  let through unsmoothed, with how many: taken for trackpad events, remote desktop
  (already smoothed), smoothing off for this event (with the switch, scroll key, app
  rule and allowlist), smoothing on but not for this axis, no display link.
- Category `logi`: what a Logitech mouse reported (battery, DPI, haptic state, press
  force, wheel mode, SmartShift threshold and wheel force; once per change), every
  decision to write or not to write and why (wheel lines start with the mouse's name and
  receiver slot, for example `[MX Master 4 slot 0x01] Wheel: Mode: ... already set, no
  write`; a value you never set is "not set by the user, left alone"), the read-back
  after a write, requests the mouse refused or did not answer, each gesture haptic cue,
  HID++ writes that took 5 ms or more (they block the thread that serves the event taps;
  at most one line a second, with how many and the longest), and once per connection the
  number of writes while connecting with their total and longest time.
- Category `app`, the app's own health: every start and stop with its cause (launch,
  sleep and wake, another user, "Pause Scrollio", the Accessibility access lost or back,
  quitting), event taps that could not be created and the retries, taps that macOS turned
  off (at most one line per tap every 10 seconds, with how many times since the last
  line), tap restarts and their throttle, the display link's recovery, the gesture
  watchdogs, and the old Mos or another copy of Scrollio being quit at launch:

  ```text
  Started (the Mac woke up): the event taps and the Logitech sessions run
  macOS turned off the scroll event tap 4 times since the last line: 4 timeouts (Scrollio's main thread answered too slowly), 0 by user input
  ```

  ```bash
  log show --last 1h --predicate 'subsystem == "com.nikklemenc.Scrollio" AND category == "app"'
  ```

Nothing in these lines identifies a person or an app's content, and nothing leaves the Mac.

## Requirements

- A Mac with macOS 14.0 or later and a recent Xcode.
- An Apple Development signing identity. The project is set to the author's team: to
  build it yourself, change `DEVELOPMENT_TEAM` to your own in the target's Signing
  settings. Do not turn signing off: the Accessibility permission is tied to the code
  signature.
- At run time: the Accessibility permission (System Settings > Privacy & Security >
  Accessibility). Scrollio asks for it on first launch. Without it no event is read
  or changed.

## Build

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build
```

This builds `Scrollio Debug.app` (bundle id `com.nikklemenc.Scrollio.debug`). For the
release app `Scrollio.app` (`com.nikklemenc.Scrollio`):

```bash
xcodebuild -scheme Debug -configuration Release -destination 'platform=macOS' build
```

Or open `Mos.xcodeproj` in Xcode and run the `Debug` scheme. The project, the targets
and the Swift modules keep the name Mos (`Mos`, `Mos_Debug`, `MosTests`).

To build the release app and put it in `/Applications`:

```bash
scripts/install.sh
```

It builds into `build/install`, stamps the build with its commit (shown under General in
Settings), and installs only a build that macOS will keep trusting: the signature must
match the installed app's (a differently signed build would be asked for the Accessibility
permission again), with no debugger entitlement and no coverage instrumentation.
`scripts/install.sh --check` builds and checks without installing.

To build the app for other people's Macs:

```bash
scripts/release.sh
```

It builds a universal Release app (Apple silicon and Intel) signed with the Developer ID
certificate, has Apple notarize it, and writes `build/release/Scrollio-<version>.dmg`. It
needs a Developer ID Application certificate in the keychain and notarization credentials
stored as the keychain profile `scrollio-notary`
(`xcrun notarytool store-credentials "scrollio-notary" --team-id <team id>`). It installs
nothing and leaves the project's signing settings as they are.
`scripts/release.sh --check` builds, signs and checks without notarizing.

## Tests

```bash
pgrep -fl "Scrollio Debug.app"     # must print nothing: quit a running debug app first
xcodebuild -scheme Debug -destination 'platform=macOS' test
xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/<TestClassName>
```

The tests run inside `Scrollio Debug.app` with its startup side effects switched off:
the app's event taps and Logitech sessions are not started, the real settings are not
written, and no login item is registered.

Never add `CODE_SIGNING_ALLOWED=NO`. It re-signs the debug app ad hoc, macOS then asks
for the Accessibility permission again, and with a running instance that prompt can
freeze mouse and keyboard input.

Tests that talk to a real Logitech mouse are skipped unless they are asked for:

```bash
LOGI_REAL_DEVICE=1 xcodebuild -scheme Debug -testPlan DebugWithDevice -destination 'platform=macOS' test
```

## Repository layout

| Path | Contents |
| --- | --- |
| `Mos/` | The app: `ScrollCore`, `ButtonCore`, `InputEvent`, `Shortcut`, `Keys`, `Logi`, `Integration`, `Options`, `Managers`, `Components`, `Windows` |
| `MosTests/` | Unit tests (XCTest) |
| `Mos.xcodeproj/` | The Xcode project, schemes `Debug` and `Profile` |
| `scripts/qa/` | The Logi boundary lint, also run by a test |
| `tools/` | Hand-run HID++ probes and a small regression harness |
| `docs/` | Design notes and plans, mostly from the original project |
| `assets/` | Images and source artwork |
| `AGENTS.md` | Rules for coding agents working in this repository |
| `LOCALIZATION.md` | How the string catalogs work |
| `CHANGELOG.md` | History of the original project up to the fork |

## Attribution and licence

Scrollio is based on **[Mos](https://github.com/Caldis/Mos)** by **Caldis**
(Copyright © 2017-2026 Caldis).

Mos is licensed under the
[Creative Commons Attribution-NonCommercial 4.0 International licence (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/),
and so is Scrollio. A summary of the licence is in [LICENSE](LICENSE); the full text is
at <https://creativecommons.org/licenses/by-nc/4.0/legalcode>.

**This work has been modified.** Scrollio is not the original Mos. Among the changes:
a new name, icon and bundle identifier; gesture navigation including the "follow the
hand" mode; a reworked smooth-scroll engine (frame-rate independent, timed to the
pointer's display, with a per-scroll diagnostic log) and simpler scroll settings;
Logitech wheel settings, device-tracked gestures and haptics; the Gestures and Mouse
preferences tabs, a main menu bar and a new welcome window; English as the only language;
removal of the Sparkle updater, the website and the release tooling; a minimum system
version of macOS 14.

**Non-commercial use only.** Neither Scrollio nor anything derived from it may be used
for commercial purposes, and it must not be distributed through the App Store.

Caldis and the contributors to Mos do not endorse Scrollio and are not responsible for
it. It comes with no warranty.

### Acknowledgements

- [Mos](https://github.com/Caldis/Mos), the project this one is built on.
- [Charts](https://github.com/danielgindi/Charts) (DGCharts), used by the scroll monitor window.
- [Solaar](https://github.com/pwr-Solaar/Solaar), a reference for the Logitech HID++ protocol.
- [Smoothscroll for websites](https://github.com/galambalazs/smoothscroll-for-websites),
  credited by Mos for its smoothing approach.
