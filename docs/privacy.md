# Permissions and privacy

## Permissions

Scrollio asks for one permission: **Accessibility** (System Settings › Privacy &
Security › Accessibility). It needs it to receive the mouse's and the keyboard's events,
smooth the scrolling, run the actions of buttons, keys and gestures, and send the key
presses those actions make. Without it, no scroll, button or key event is changed. The
Welcome Guide leads you to the switch.

With "Trackpad-style scrolling (Experimental)" on, the same permission is used for one more
thing, and only for a wheel scroll in an app that gets the one-touch form: an app that is
not known to be built on Chromium or on Firefox's engine, is not Safari or DuckDuckGo, and
is not one of the apps left alone by name. (An Electron app is no browser and is not
read; a WebKit browser other than those two, Orion for one, is read like any other app.)
While such a scroll runs, and for each wheel event it takes in at a page's end, Scrollio
asks that app which kind of element is under the pointer, which kinds its containers are
up to the first scroll area (never further than the window), and where that area's
vertical scroll bar stands. Only a bar that counts from 0 to 1 and is not disabled is
used: its maximum, where the app tells one, whether it is enabled, and every value are
checked. Where no bar is seen it asks the element under the pointer for its position
and size, once per display frame while the scroll runs, to see whether it moves with
the wheel. It reads no title, no text and no other value. It never asks macOS for the
permission by itself for this: where the access is missing, nothing is read.

The app itself (its application element) is asked one thing only: which element is under
the pointer. Chrome and Electron apps switch on their accessibility support when the
application is asked what it is, so Scrollio never asks that, in any app. And an app is
not looked at before Scrollio knows whether it is built on Chromium.

Dia and Arc (Chromium inside a program of their own; Scrollio knows such an app by the
engine in its bundle and the missing application class in its `Info.plist`) are read
too, with "In browsers" on: once per place the wheel is used at, and for the scrolls
over what is not a page. There is one more rule for them: no element is asked what it is
before it has shown a vertical scroll bar. The view that holds a web page would switch
on Chromium's accessibility support at that question. It is asked whether it has such a
bar (it has none), for its parent, how many children it has, where it is and how large,
and which window it is in; and the app is asked once more which element is 40 points
away. The scroll log keeps these as numbers.

With "In Mac apps" off, an app that is no browser is asked nothing at all; with "In
browsers" off, neither is a browser, Dia and Arc included.

"Open at login" registers Scrollio as a login item; macOS may ask you to approve it in
System Settings under Login Items.

Key presses pass through Scrollio only while a key is bound to an action in Buttons,
while a button you hold stands for a modifier, or while you record a key in Settings.
Otherwise it only listens to them, for the keys under Scrolling › While you hold a key,
and cannot delay them.

A script a button runs is started as a program of its own: it has none of Scrollio's
permissions (not its Accessibility access), and macOS asks for the script's own when it
needs one. On a macOS without the function for this, it runs as Scrollio's child with
Scrollio's permissions, and the `app` log says so. More in [SECURITY.md](../SECURITY.md).

## Privacy

- The only network requests Scrollio makes are the updater's, and only in a released
  copy: it asks GitHub for the file `appcast.xml` of the newest release (once a day
  while "Check for updates automatically" is on, and when you choose "Check for
  Updates…" or "Check Now"), and it downloads the disk image from GitHub when an update
  is installed. Such a request shows GitHub what every web request shows, your IP
  address, and carries two things more: the app and its version
  (`Scrollio/1.0.1 Sparkle/2.10.1`) and the languages you prefer, which macOS adds to a
  web request. Nothing about your Mac or your settings is added: Sparkle's system
  profile is off and empty. With the switch off and no check asked for, a released copy
  makes no request either; a copy built from source never makes one.
- There is no analytics and no crash reporter. The "Open" button next to "Scrollio on
  GitHub" (General) hands the page to your web browser.
- Nothing else leaves your Mac. The settings are kept in Scrollio's preferences (the
  updater's own among them: your two choices and the time of the last check), and its
  log goes to the macOS system log on the Mac (see [Diagnostics](troubleshooting.md#diagnostics)).
- A [settings file](features.md#settings-file) is written only where you save it, and the settings
  from before an import only into Scrollio's folder in Application Support; neither is
  sent anywhere. Such a file holds the paths of the apps on your list and of the apps,
  files and scripts your buttons open, and a path usually contains your account name:
  look at a file before you pass it on.
- Scrollio keeps no record of what you type. When key presses pass through it at all is
  under [Permissions](#permissions); what it logs is under [Diagnostics](troubleshooting.md#diagnostics).
- Besides its own settings, Scrollio reads:
  - the macOS keyboard shortcuts for Spaces (to run them), the keyboard layout in use
    (to press the right key for shortcuts such as ⌘A, and to name keys) and the macOS
    setting for natural scrolling (for "Follow the hand");
  - which app is under the pointer or in front, for the per-app settings and "Smooth
    Scrolling in …". With "Trackpad-style scrolling (Experimental)" on, for a wheel scroll in an
    app that gets the one-touch form, it reads the kind of the element under the pointer
    and the position of that view's scroll bar (see [Permissions](#permissions) for
    which apps and when); the scroll log gets the kinds met ("AXRow", "AXScrollArea": a
    dozen at most, each cut to 40 characters) and the bar's position, nothing else.
    With "Trackpad-style scrolling (Experimental)" on it also looks once into the
    bundle of each app that comes to the front or that you scroll in, to see whether the
    app is built on Chromium or on Firefox's engine (the names in `Contents/Frameworks`,
    and whether `Contents/MacOS` holds a browser's app loader or Firefox's engine), and
    for an app built on Chromium whether its `Info.plist` names an application class
    (`NSPrincipalClass`; nothing else of that file is used); only apps in the
    Applications folders and in /System are looked into;
  - the running apps, with their names and icons, to offer them in the Apps pane;
  - the macOS pointer settings, which it shows, and changes only as described under
    [Logitech MX mice](features.md#logitech-mx-mice).
