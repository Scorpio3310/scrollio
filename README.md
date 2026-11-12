# Scrollio

![Licence: CC BY-NC 4.0](https://img.shields.io/badge/licence-CC%20BY--NC%204.0-lightgrey.svg)
![macOS 14 or later](https://img.shields.io/badge/macOS-14%2B-blue.svg)
![Swift 5](https://img.shields.io/badge/Swift-5-orange.svg)

<img src="assets/readme/app-icon.png" alt="Scrollio's icon: a white mouse on a purple tile" width="128" height="128">

**Smooth, trackpad-like scrolling for any mouse.**

Scrollio is a menu bar app for macOS. It makes a mouse's scroll wheel glide like a
trackpad, lets mouse buttons and keys run actions, adds mouse gestures and settings for
the sideways (thumb) wheel, and can manage the settings of Logitech MX mice.

It is based on [Mos](https://github.com/Caldis/Mos) by Caldis, may be used only for
non-commercial purposes, and is not affiliated with Logitech. See
[Licence and credits](#-licence-and-credits).

There is no ready-made download yet. To use Scrollio now, build it from source: see
[Build from source](#-build-from-source).

---

## ✨ Features

- ✅ **Smooth scrolling** – each click of the wheel glides out like a trackpad, in five feels from Direct to Float.
- ✅ **Per-app settings** – an app follows the Scrolling settings or keeps its own, or is left to macOS.
- ✅ **Buttons and keys** – give a mouse button, or a key with modifiers, a shortcut, a system action or an app to open.
- ✅ **Mouse gestures** – hold a button and move the mouse to switch desktops, open Mission Control and more.
- ✅ **Thumb wheel actions** – the sideways wheel can scroll, zoom, switch tabs or desktops, go back and forward, or set the volume.
- ✅ **Logitech MX settings** – battery, pointer speed, wheel mode and haptics of a Logitech MX mouse.
- ✅ **Menu bar item** – battery, Pause, and smoothing on or off for the app in front; the icon can be hidden.
- ✅ **No network** – no analytics, no crash reporter, no updater: nothing leaves your Mac.

---

## 📸 Screenshots

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/readme/scrolling-dark.png">
  <img src="assets/readme/scrolling-light.png" width="520" alt="The Scrolling pane: smooth scrolling on, the Smooth feel chosen, the speed slider and Reverse wheel direction">
</picture>

<table>
  <tr>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="assets/readme/buttons-dark.png">
        <img src="assets/readme/buttons-light.png" width="400" alt="The Buttons pane with an MX Master 4: a drawing of the mouse with the gesture button lit, and the mouse's buttons in the order they sit, each with its action">
      </picture>
      <p><b>Buttons</b>: an MX Master 4's buttons in the order they sit on the mouse.</p>
    </td>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="assets/readme/mouse-dark.png">
        <img src="assets/readme/mouse-light.png" width="400" alt="The Mouse pane with an MX Master 4: battery, tracking speed, Let Scrollio manage this mouse, pointer speed in DPI and the scroll wheel's mode">
      </picture>
      <p><b>Mouse</b>: the settings of a Logitech MX mouse.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="assets/readme/gestures-dark.png">
        <img src="assets/readme/gestures-light.png" width="400" alt="The Gestures pane: a moving preview, the gesture button, the mode, and an action for each direction">
      </picture>
      <p><b>Gestures</b>: an action for each direction.</p>
    </td>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="assets/readme/welcome-guide-dark.png">
        <img src="assets/readme/welcome-guide-light.png" width="400" alt="The Welcome Guide: choose how scrolling feels, from Direct to Float">
      </picture>
      <p><b>Welcome Guide</b>: choose how scrolling feels.</p>
    </td>
  </tr>
</table>

---

## 🔍 In detail

Settings are in one window with a sidebar: Scrolling, Buttons, Gestures, Mouse, Apps and
General. On the first launch a Welcome Guide leads through Accessibility access, the feel
of scrolling and the menu bar icon.

### Smooth scrolling

- Five feels (Direct, Quick, Smooth, Glide and Float) set how long the page glides on;
  Speed sets how far one click moves it. A moving preview in the Scrolling pane shows the
  feel.
- Reverse wheel direction (the wheel only, not the trackpad).
- Under Advanced: an exact glide time, the smallest step, and
  "Trackpad-style events (Beta)": apps treat the wheel like a trackpad and bounce at the
  ends of a page. Safari gets none of these events.
- While you hold a key: "Scroll faster" (5 × the distance), "Scroll sideways" and "Pause
  smoothing" (exact steps, for example to zoom with ⌘). A mouse button can hold them
  too.
- Per app (the Apps pane): an app uses the Scrolling settings or keeps its own. "Limit
  scrolling to these apps" leaves every other app to macOS; buttons and gestures still
  work everywhere. "Smooth Scrolling in …" in the menu bar menu turns smoothing on or off
  for the app in front.
- Trackpads and the Magic Mouse are left alone. With several displays, the motion is
  timed to the display under the pointer.

### Buttons and keys

- The actions: a system shortcut (Mission Control and Spaces, apps and windows, editing,
  Finder, screenshots, navigation and more), a keyboard shortcut you record, a modifier
  key, another mouse button, one of the scroll keys, Gesture Navigation, or opening an
  app, a file or a script.
- A drawing of the mouse lights the button each row is about. With an MX Master, its
  buttons are listed in the order they sit on the mouse, and any other buttons and keys
  under them:
  - MX Master 4: Middle button, Mode shift button, Thumb wheel, Gesture button, Forward
    button, Back button, Thumb panel.
  - MX Master 3 and 3S: Middle button, Mode shift button, Thumb wheel, Forward button,
    Back button, Gesture button.
- On a Logitech mouse, buttons that macOS does not report (such as the gesture button,
  the mode shift button and the thumb panel) can have actions too, and a Logitech button
  can run Logitech actions: switch the wheel mode, change the pointer speed, switch to
  another computer, and more.
- A row says when its button is also a scroll key, or when another app (Logi Options+)
  may take it over.
- Removing a button or an app can be undone (Edit › Undo).

### Mouse gestures

- Hold the button that has the action Gesture Navigation and move the mouse: up, down,
  left and right each run an action, and letting go without moving runs one more.
- Two modes: "One action per hold", and "Follow the hand", in which moving sideways
  slides the desktops with your hand, like a trackpad swipe. "Follow the hand" uses a
  private macOS interface; where it is missing, the mode is not available.
- "Freeze pointer during a gesture" keeps the pointer where it is while you hold the
  button.
- With a Logitech MX Master, the mouse can track the gesture itself (experimental), and an
  MX Master 4 can pulse when a gesture locks in.

### Thumb wheel

The sideways wheel (an MX Master's thumb wheel, or a wheel that tilts) has its own
settings, under Scrolling › Thumb wheel and, with an MX Master, in the Thumb wheel row of
the Buttons pane. They apply to every app.

- Action: Scroll Sideways (the default), Zoom, Switch Tabs, Switch Desktops, Back and
  Forward, or Volume.
- Speed, and Swap direction.

### Logitech MX mice

The Mouse pane shows a connected Logitech mouse's battery and, on mice that support them,
its settings:

- Sensor: Pointer speed (DPI).
- Scroll wheel: Wheel mode (SmartShift, Ratchet or Free-spin), SmartShift sensitivity and
  Click firmness.
- Haptics (MX Master 4): Haptic feedback and its strength, and how hard the thumb panel
  must be pressed.

Scrollio writes these settings to the mouse only while "Let Scrollio manage this mouse"
is on, and then only the values you set that the mouse does not already have, again each
time it connects. While the switch is off, the pane shows what the mouse reports. Do not
run Logi Options+ at the same time.

Apart from those settings: for a Logitech-only button that has an action, Scrollio asks
the mouse to send that button to Scrollio (and gives it back when Scrollio pauses or
quits); a Logitech action you give a button changes the mouse when you press it; and the
gesture pulse can switch the mouse's haptics on, unless Haptic feedback is turned off.

Logitech mice work over a Logitech receiver (Bolt or Unifying) or Bluetooth. A low
battery gets one notice at 10 % and one at 5 %, and its percentage stands next to the
menu bar icon until the mouse charges.

The same pane has two macOS settings for every mouse, "Tracking speed" and "Pointer
acceleration", as in System Settings › Mouse. Scrollio changes them only when you move
those controls.

### Menu bar

- The menu lists each Logitech mouse's battery, "Smooth Scrolling in …" for the app in
  front, "Pause Scrollio" or "Resume Scrollio", "Settings…" and "Quit Scrollio". A pause
  stops everything and gives the Logitech mice their buttons back; it is not kept after
  Scrollio quits. With Option held the menu also lists Logitech Diagnostics, a developer
  window with the HID++ details of the connected mice.
- The icon is dimmed while Scrollio is paused, waits for Accessibility access, or could
  not start and tries again; its tooltip says which.
- The icon can be hidden (General › Show in menu bar). Opening Scrollio again then shows
  its settings, or the Welcome Guide while Accessibility access is missing.
- General also has "Open at login" and the state of the Accessibility access.
- Scrollio stops while the Mac sleeps or another user has it, and starts again when you
  are back.
- At launch, and whenever Mos starts later, it quits a running Mos: two apps would both
  handle the same mouse events. Mos's settings are not read.

---

## 💻 Requirements

- macOS 14 or later.
- Any mouse for scrolling, buttons and gestures. The Mouse pane's settings, the button
  list in mouse order and the mouse drawings are for Logitech MX mice (the drawings: MX
  Master 4, MX Master 3 and 3S, and a generic mouse).

---

## 🔐 Permissions

Scrollio asks for one permission: **Accessibility** (System Settings › Privacy &
Security › Accessibility). It needs it to receive the mouse's and the keyboard's events,
smooth the scrolling, run the actions of buttons, keys and gestures, and send the key
presses those actions make. Without it, no scroll, button or key event is changed. The
Welcome Guide leads you to the switch.

"Open at login" registers Scrollio as a login item; macOS may ask you to approve it in
System Settings under Login Items.

---

## 🔒 Privacy

- Scrollio makes no network connections: there is no networking code in it, no
  analytics, no crash reporter and no updater. The "Open" button next to "Scrollio on
  GitHub" (General) hands the page to your web browser.
- Nothing leaves your Mac. The settings are kept in Scrollio's preferences, and its log
  goes to the macOS system log on the Mac (see [Diagnostics](#-diagnostics)).
- Besides its own settings, Scrollio reads the macOS keyboard shortcuts for Spaces (to
  run them), and changes the macOS pointer settings only as described under
  [Logitech MX mice](#logitech-mx-mice).

---

## 🔨 Build from source

You need a Mac with macOS 14 or later, Xcode 26 or later (the app icon is an Icon
Composer file) and an Apple Development signing identity. The project is set to the
author's team: set `DEVELOPMENT_TEAM` to your own in the target's Signing settings. Do
not turn signing off: macOS ties the Accessibility permission to the code signature.

To build the release app and install it in `/Applications`:

```bash
scripts/install.sh            # build, check, install, start
scripts/install.sh --check    # build and check only; nothing is installed
```

The script builds into `build/install` (or `$SCROLLIO_DERIVED_DATA`) and stamps the build
with its commit and date (shown under General). It installs a build only when:

- its signature verifies, is made with a certificate (not ad hoc) and has the same
  designated requirement as the installed app (a differently signed build would be asked
  for the Accessibility permission again);
- its bundle identifier is `com.nikklemenc.Scrollio`;
- it carries no debugger entitlement (`get-task-allow`) and no code-coverage
  instrumentation.

It then quits the running copy, replaces `/Applications/Scrollio.app`, registers it again
with macOS so the Dock and Finder show the current icon, and opens it.

Plain builds:

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build    # Scrollio Debug.app
xcodebuild -scheme Debug -configuration Release -destination 'platform=macOS' build  # Scrollio.app
```

The debug build is a separate app, `Scrollio Debug.app` (`com.nikklemenc.Scrollio.debug`).

---

## 🩺 Diagnostics

Scrollio writes what it did to the macOS system log, subsystem `com.nikklemenc.Scrollio`
(`com.nikklemenc.Scrollio.debug` for the debug build), in three categories. Nothing is
logged per event.

```bash
# the last ten minutes
log show --last 10m --predicate 'subsystem == "com.nikklemenc.Scrollio"'
# one category, the last hour
log show --last 1h --predicate 'subsystem == "com.nikklemenc.Scrollio" AND category == "app"'
# live
log stream --predicate 'subsystem == "com.nikklemenc.Scrollio" AND category == "scroll"'
```

- `scroll`: one line per finished scroll, what the wheel asked for and what was sent:

  ```text
  scroll: 5 wheel events 2140 px in -> 61 frames 2112 px out (largest 98.4), wheel 44 ms,
  glide after the last event 820 ms, Duration 4.50 (tau 230 ms), trackpad-style off, ended MomentumEnd
  ```

  Also one `thumb wheel:` line per roll of the sideways wheel, and at most one line per
  reason every 3 seconds while wheel events are let through unsmoothed (trackpad events,
  a remote desktop, smoothing off for that event, no display link).
- `logi`: what a Logitech mouse reported (battery, pointer speed, haptics, press force,
  wheel settings), each decision to write a value or not and why, the read-back after a
  write, requests the mouse refused or did not answer, gesture haptic cues, and slow
  writes.
- `app`: Scrollio's own health: each start and stop with its cause (launch, sleep and
  wake, another user, Pause, Accessibility access lost or back, quit), event taps that
  could not be created or that macOS turned off, restarts, and at launch which accent
  colour is in effect:

  ```text
  Accent colour: the app's own (purple)
  Started (the Mac woke up): the event taps and the Logitech sessions run
  ```

---

## 📄 Licence and credits

Scrollio is based on **[Mos](https://github.com/Caldis/Mos)** by **Caldis** and its
contributors. Mos is licensed under the
[Creative Commons Attribution-NonCommercial 4.0 International licence (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/),
and so is Scrollio. A summary of the licence is in [LICENSE](LICENSE); the full text is at
<https://creativecommons.org/licenses/by-nc/4.0/legalcode>.

**This work has been modified.** Scrollio is not the original Mos. Among the changes: a
new name, icon and bundle identifier; a reworked smooth-scrolling engine and simpler
scroll settings; the "Follow the hand" gesture mode; the thumb wheel's actions; settings
for Logitech MX mice (pointer speed, wheel, haptics, press force) and gestures tracked by
the mouse; the Mouse and Gestures panes, a battery in the menu bar, a main menu and a new
Welcome Guide; English as the only language; the Sparkle updater and the original
website and release tooling removed; macOS 14 as the minimum. The history of Mos up to
the fork is in its own repository, in its
[changelog](https://github.com/Caldis/Mos/blob/master/CHANGELOG.md) and its git history.

**Non-commercial use only.** Neither Scrollio nor anything derived from it may be used
for commercial purposes.

Caldis and the contributors to Mos do not endorse Scrollio and are not responsible for
it. Scrollio is not affiliated with or endorsed by Logitech. It comes with no
warranty.

### Acknowledgements

- [Mos](https://github.com/Caldis/Mos), the project Scrollio is built on.
- [Charts](https://github.com/danielgindi/Charts) (DGCharts), used by the debug build's
  scroll monitor window.
- [Solaar](https://github.com/pwr-Solaar/Solaar), a reference for the Logitech HID++
  protocol.
- [Smoothscroll for websites](https://github.com/galambalazs/smoothscroll-for-websites),
  credited by Mos for its smoothing approach.

---

## 🧑‍💻 For developers

```bash
pgrep -fl "Scrollio Debug.app"     # must print nothing: quit a running debug app first
xcodebuild -scheme Debug -destination 'platform=macOS' test
xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:ScrollioTests/<TestClassName>
scripts/qa/lint-logi-boundary.sh
```

The tests run inside `Scrollio Debug.app` with its startup side effects switched off:
the event taps and Logitech sessions are not started, the real settings are not written
and no login item is registered. Never add `CODE_SIGNING_ALLOWED=NO`: it re-signs the
debug app ad hoc, macOS then asks for the Accessibility permission again, and with a
running instance that prompt can freeze mouse and keyboard input. Tests that talk to a
real Logitech mouse run only when asked for:

```bash
LOGI_REAL_DEVICE=1 xcodebuild -scheme Debug -testPlan DebugWithDevice -destination 'platform=macOS' test
```

A build for other people's Macs is made with `scripts/release.sh`:

```bash
scripts/release.sh --check    # universal build signed with Developer ID, and its checks; nothing is notarized
scripts/release.sh            # the same, then notarized by Apple and packed into a disk image
```

It builds a universal Release app (Apple silicon and Intel) signed with the Developer ID
certificate, has Apple notarize the app and the disk image, and writes
`build/release/Scrollio-<version>.dmg`. It needs a Developer ID Application certificate
in the keychain and notarization credentials stored as the keychain profile
`scrollio-notary` (`xcrun notarytool store-credentials "scrollio-notary" --team-id <team id>`).
It installs nothing and leaves the project's signing settings as they are: the release
signature is not the development signature of the copy in `/Applications`.

| Path | Contents |
| --- | --- |
| `Scrollio/` | The app: `ScrollCore`, `ButtonCore`, `InputEvent`, `Shortcut`, `Keys`, `Logi`, `Integration`, `MacPointer`, `Options`, `Managers`, `Components`, `Windows`, `Utils` |
| `ScrollioTests/` | Unit tests (XCTest) |
| `Scrollio.xcodeproj/` | The Xcode project, schemes `Debug` and `Profile` |
| `scripts/` | `install.sh`, `release.sh`, and in `qa/` the Logitech boundary lint (also run by a test) |
| `tools/` | Hand-run HID++ probes and a small regression harness (see its README before running a probe) |
| `assets/` | The pictures of this README |
| `AGENTS.md` | Rules for coding agents and contributors: build, tests, signing, module boundaries, strings |
