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
non-commercial purposes, and is not affiliated with Apple or Logitech. See
[Licence and credits](#-licence-and-credits).

Download the latest disk image from the
[Releases page](https://github.com/Scorpio3310/scrollio/releases); what is in it, and how
to check it, is under [Download and first launch](#-download-and-first-launch). Or
[build it from source](docs/development.md#build-from-source).

The website, [scrollio.klemenc.dev](https://scrollio.klemenc.dev/), shows Scrollio at a
glance, with the features, help and what is new.

---

## ✨ Features

- ✅ **Smooth scrolling** – each click of the wheel glides out like a trackpad, in five feels from Direct to Float.
- ✅ **Per-app settings** – an app follows the Scrolling settings or keeps its own, or is left to macOS.
- ✅ **Buttons and keys** – give a mouse button, or a key with modifiers, a shortcut, a system action or an app to open.
- ✅ **Mouse gestures** – hold a button and move the mouse to switch desktops, open Mission Control and more.
- ✅ **Shortcut Ring** – a button or a key opens a ring of eight shortcuts around the pointer: hold and move, or press and click.
- ✅ **Thumb wheel actions** – the sideways wheel can scroll, zoom, switch tabs or desktops, go back and forward, or set the volume.
- ✅ **Logitech MX settings** – battery, pointer speed, wheel mode and haptics of a Logitech MX mouse.
- ✅ **Menu bar item** – battery, Pause, and smoothing on or off for the app in front; the icon can be hidden.
- ✅ **Settings in a file** – export all your settings to one file and import them on another Mac; an import shows first what the file holds and keeps your settings from before.
- ✅ **Updates itself** – a released Scrollio asks GitHub once a day for a newer version, if you allow it, and installs only what carries the author's signature.
- ✅ **No tracking** – no analytics, no crash reporter. The update check is the only network request, and you can switch it off.

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
        <img src="assets/readme/gestures-light.png" width="400" alt="The Gestures pane: a moving preview, the button to hold, the mode, and an action for each direction">
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

## 💻 Requirements

- macOS 14 or later.
- Any mouse for scrolling, buttons and gestures. The Mouse pane's settings, the button
  list in mouse order and the mouse drawings are for Logitech MX mice (the drawings: MX
  Master 4, MX Master 3 and 3S, and a generic mouse).

---

## 📥 Download and first launch

Get the latest `Scrollio-<version>.dmg` from the
[Releases page](https://github.com/Scorpio3310/scrollio/releases). (The other way to get
Scrollio is to [build it from source](docs/development.md#build-from-source).) Later versions arrive as
[updates](docs/features.md#updates); only 1.0.0 has to be replaced by hand.

A release is one disk image, `Scrollio-<version>.dmg`, for Apple silicon and Intel
Macs. The app in it and the image itself are signed with the author's Developer ID
(team `8C592KLVN6`) and notarized by Apple. A download from anywhere else, or one signed
by anyone else, is not an official build.

1. Open the disk image and drag Scrollio to the Applications folder. Open it from there,
   not from the disk image: opened from the image, Scrollio asks to be moved first.
2. macOS asks once whether to open an app that was downloaded from the internet.
3. The Welcome Guide opens. "Open Accessibility Settings" takes you to System Settings ›
   Privacy & Security › Accessibility: turn on Scrollio in the list. Until you do,
   Scrollio changes no scroll, button or key event.
4. Choose how scrolling feels, and whether Scrollio opens at login. It then runs in the
   menu bar; click its icon for Settings, Pause and Quit.

If Mos is running, Scrollio quits it once Accessibility access is there, and says so
(see [Menu bar](docs/features.md#menu-bar)). To go back to Mos, pause or quit Scrollio.

To check a download before you open it:

```bash
# the same sum as in the release notes
shasum -a 256 ~/Downloads/Scrollio-<version>.dmg
# "accepted", "source=Notarized Developer ID"
spctl -a -vv -t open --context context:primary-signature ~/Downloads/Scrollio-<version>.dmg
```

And the app, once it is in Applications:

```bash
# "accepted", "source=Notarized Developer ID"
spctl -a -vv /Applications/Scrollio.app
# "TeamIdentifier=8C592KLVN6"
codesign -dv --verbose=2 /Applications/Scrollio.app 2>&1 | grep -E "Authority|TeamIdentifier"
```

---

## 📚 More

Settings are in one window with a sidebar: Scrolling, Buttons, Gestures, Shortcut Ring,
Mouse, Apps and General. On the first launch a Welcome Guide leads through Accessibility access, the feel
of scrolling and the menu bar icon. The details are in `docs/`:

- [Smooth scrolling](docs/scrolling.md): the feels, per-app settings, the keys that change
  a scroll, and Trackpad-style scrolling (Experimental): where it works and where not.
- [Buttons, gestures, the Shortcut Ring, the thumb wheel and the rest](docs/features.md):
  actions for buttons and keys, mouse gestures, the Shortcut Ring, the thumb wheel,
  Logitech MX mice, the menu bar, the settings file and updates.
- [Permissions and privacy](docs/privacy.md): what Scrollio asks macOS for and why, and
  what it reads, keeps and sends.
- [Uninstalling and diagnostics](docs/troubleshooting.md): removing Scrollio completely,
  and reading its log when something is wrong.
- [Building and releasing](docs/development.md): building from source, the project's
  layout and how a release is made.
- [CHANGELOG.md](CHANGELOG.md): what changed in each version.
- [scrollio.klemenc.dev](https://scrollio.klemenc.dev/): the website, with the features
  at a glance, help, what is new and the privacy policy.

---

## 🔐 Permissions and privacy, in short

- Scrollio needs **Accessibility** access: without it macOS lets no app read or change
  what a mouse does. It asks for nothing else.
- **No tracking**: no analytics, no crash reporter, no account. The only network request
  is the update check of a released copy, once a day if you allow it; it sends none of
  your settings or data.
- With Trackpad-style scrolling (Experimental) and "In Mac apps" on, Scrollio reads where
  the scroll bar or the content under the pointer is, to know where a page ends. It keeps
  and sends none of it.

The whole of it: [Permissions and privacy](docs/privacy.md).


---

## 📄 Licence and credits

Scrollio is a modified version of **[Mos](https://github.com/Caldis/Mos)** by **Caldis**
and its contributors.

- Mos: Copyright © 2017–2026 Caldis and contributors.
- Scrollio's changes: Copyright © 2026 Nik Klemenc.

Mos is licensed under the
[Creative Commons Attribution-NonCommercial 4.0 International licence (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/),
and so is Scrollio. [LICENSE](LICENSE) holds these notices and the full text of the
licence.

**This work has been modified.** Scrollio is not the original Mos. Among the changes: a
new name, icon and bundle identifier; a reworked smooth-scrolling engine and simpler
scroll settings; the "Follow the hand" gesture mode; the thumb wheel's actions; settings
for Logitech MX mice (pointer speed, wheel, haptics, press force) and gestures tracked by
the mouse; the Mouse and Gestures panes, a battery in the menu bar, a main menu and a new
Welcome Guide; English as the only language; the original website and release tooling
removed, and updates set up anew (Sparkle 2, fed from this repository's GitHub
releases); macOS 14 as the minimum. The history of Mos up to
the fork is in its own repository, in its
[changelog](https://github.com/Caldis/Mos/blob/master/CHANGELOG.md) and its git history.

**Non-commercial use only.** Neither Scrollio nor anything derived from it may be used
for commercial purposes.

Caldis and the contributors to Mos do not endorse Scrollio and are not responsible for
it. Scrollio comes with no warranty.

Scrollio is not affiliated with or endorsed by Apple or Logitech. Apple, Mac and macOS
are trademarks of Apple Inc.; Logitech, MX Master, Logi Options+ and the other Logitech
product names used here are trademarks of Logitech.

### Acknowledgements

- [Mos](https://github.com/Caldis/Mos), the project Scrollio is built on.
- [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) by Noah Nübling, the
  reference for the events behind "Follow the hand". Scrollio's code for it is its own,
  written from what Mac Mouse Fix's source shows, and so derived from it: the layout of
  the Dock swipe events (the event fields, and the HID event the Dock reads on macOS 27),
  the empty event that follows each of them, the 63 pt gap the Dock draws between two
  desktops, how a swipe's progress scales with the number of desktops, sending the final
  event again after 0.2 and 0.5 seconds, the travel after which a hold locks to a
  direction, and the pointer's late jump after it is moved back on macOS 27.
- [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher), a second
  reference for the format of the same events and its pitfalls (MIT licence).
- [Solaar](https://github.com/pwr-Solaar/Solaar), a reference for the Logitech HID++
  protocol: battery, pointer speed, the wheel, haptics, press force and the flags of a
  button's reporting. The names of the Logitech controls and the list of Logitech
  receivers are Solaar's tables (`special_keys.py` and `base_usb.py`), taken over with
  Mos. Solaar is licensed under the GNU General Public License, version 2.
- [OpenLogi](https://github.com/AprilNEA/OpenLogi), a reference for the same HID++
  features (pointer speed, battery, haptic feedback, press force, SmartShift), for the
  layout of an error answer, and for gestures tracked by the mouse: the haptic waveforms
  that are played and the jump in the first movement sample.
- [logiops](https://github.com/PixlOne/logiops), a reference for gestures tracked by the
  mouse (a button's raw movement and the haptic pulses).
- [Mouser](https://github.com/TomBadash/Mouser), a reference for battery, press force,
  the wheel and gestures tracked by the mouse.
- [Smoothscroll for websites](https://github.com/galambalazs/smoothscroll-for-websites),
  credited by Mos for its approach to smoothing.
- [Charts](https://github.com/danielgindi/Charts) (DGCharts, Apache License 2.0) draws
  the graph of the debug build's Scroll Monitor. The release app is built without it.
- [Sparkle](https://github.com/sparkle-project/Sparkle) (MIT licence) is the updater of
  the released app: it is embedded as it is distributed, and its helper programs are
  signed with Scrollio's Developer ID. Its licence names the code it includes, among it
  the [Ed25519 implementation](https://github.com/orlp/ed25519) by Orson Peters.

The same list, with the licences of Charts and Sparkle, is in
[Scrollio/Acknowledgements.txt](Scrollio/Acknowledgements.txt), which is part of the app
and of the disk image.

---

## 🤝 Contributing and security

Scrollio is one person's project. Issues are welcome; pull requests are read, but may
wait, and not every one will be merged: [CONTRIBUTING.md](CONTRIBUTING.md). A security
problem is reported privately, not in an issue: [SECURITY.md](SECURITY.md).
