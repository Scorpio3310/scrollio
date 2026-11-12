# Buttons, gestures, the thumb wheel and the rest

What each part of Scrollio does, beyond scrolling. Scrolling itself, with
Trackpad-style scrolling (Experimental), is in [scrolling.md](scrolling.md).

## Buttons and keys

- The actions: a system shortcut (Mission Control and Spaces, apps and windows, editing,
  Finder, screenshots, navigation and more), a keyboard shortcut you record, a modifier
  key, another mouse button, one of the scroll keys, Gesture Navigation, or opening an
  app, a file or a script.
- The listed shortcuts (Select All, Undo, Copy and the rest) press the right key on every
  keyboard layout, and keys are named as your keyboard names them.
- To record a button or a key, click + and press it. Esc, a left click, closing the
  popover or switching to another app ends the recording.
- A drawing of the mouse lights the button each row is about. The MX Master 4 and the
  MX Master 3 and 3S are drawn from above and from their thumb side, where the thumb
  wheel, the side buttons and the thumb panel (or the gesture button in the thumb rest)
  are: the drawing turns to the side the row's button is on. With an MX
  Master, its buttons are listed in the order they sit on the mouse, and any other
  buttons and keys under them:
  - MX Master 4: Middle button, Mode shift button, Thumb wheel, Gesture button, Forward
    button, Back button, Thumb panel.
  - MX Master 3 and 3S: Middle button, Mode shift button, Thumb wheel, Forward button,
    Back button, Gesture button.
- On a Logitech mouse, buttons that macOS does not report (such as the gesture button,
  the mode shift button and the thumb panel) can have actions too. With a Logitech mouse
  connected, a button, a key or a gesture can also run a Logitech action: switch the
  wheel mode, change the pointer speed, or switch the mouse to another computer.
- A row says when its button is also a scroll key, or when another app (Logi Options+)
  may take it over.
- Removing a button or an app can be undone (Edit › Undo).

## Mouse gestures

- Hold the button that has the action Gesture Navigation and move the mouse: up, down,
  left and right each run an action, and letting go without moving runs one more.
- Two modes: "One action per hold", and "Follow the hand", in which moving sideways
  slides the desktops with your hand, like a trackpad swipe. "Follow the hand" uses a
  private macOS interface; where it is missing, the mode is not available.
- "Freeze pointer during a gesture" keeps the pointer where it is while you hold the
  button.
- With a Logitech MX Master, the mouse can track the gesture itself (Beta), and an MX
  Master 4 can pulse when a gesture locks in.

## Thumb wheel

The sideways wheel (an MX Master's thumb wheel, or a wheel that tilts) has its own
settings, under Scrolling › Thumb wheel and, with an MX Master, in the Thumb wheel row of
the Buttons pane. They apply to every app.

- Action: Scroll Sideways (the default), Zoom, Switch Tabs, Switch Desktops, Back and
  Forward, or Volume.
- Speed, and Swap direction.

## Logitech MX mice

The Mouse pane shows a connected Logitech mouse's battery and, on mice that support them,
its settings:

- Sensor: Pointer speed (DPI), a step every 200 from 400 to 4000.
- Scroll wheel: Wheel mode (SmartShift, Ratchet or Free-spin), SmartShift sensitivity and
  Click firmness.
- Haptics (MX Master 4): Haptic feedback and its strength, and how hard the thumb panel
  must be pressed.

Scrollio writes these settings to the mouse only while "Let Scrollio manage this mouse"
is on, and then only the values you set that the mouse does not already have, again each
time it connects. While the switch is off, the pane shows what the mouse reports. Do not
run Logi Options+ at the same time.

Apart from those settings, and whatever that switch says:

- For a Logitech-only button that has an action, and for a gesture button the mouse
  tracks itself, Scrollio asks the mouse to send that button to Scrollio, and gives it
  back when Scrollio pauses or quits.
- While you record a button in the Buttons pane, Scrollio asks the mouse for every
  button it can send (never the left or the right one), so that it can tell which one
  you press, and gives them back when the recording ends.
- A Logitech action changes the mouse when its button, key or gesture runs it.
- The gesture pulse plays on the mouse and can switch its haptics on, unless Haptic
  feedback is turned off.

A value written to the mouse is stored in the mouse: it stays after Scrollio quits or is
removed. If a Logitech button stops working after Scrollio crashed or was force quit,
switch the mouse off and on.

Logitech mice work over a Logitech receiver (Bolt or Unifying) or Bluetooth. A low
battery gets one notice at 10 % and one at 5 %, and its percentage stands next to the
menu bar icon until the mouse charges.

The same pane has two macOS settings for every mouse, "Tracking speed" and "Pointer
acceleration", as in System Settings › Mouse. Scrollio changes them only when you move
those controls.

## Menu bar

- The menu lists each Logitech mouse's battery, "Smooth Scrolling in …" for the app in
  front, "Pause Scrollio" or "Resume Scrollio", "Settings…" and "Quit Scrollio". A pause
  stops everything and gives the Logitech mice their buttons back; it is not kept after
  Scrollio quits. With Option held the menu also lists Logitech Diagnostics, a developer
  window with the HID++ details of the connected mice. In the released app it only reads.
- The icon is dimmed while Scrollio is paused, waits for Accessibility access, or could
  not start and tries again; its tooltip says which.
- The icon can be hidden (General › Show in menu bar). Opening Scrollio again then shows
  its settings, or the Welcome Guide while Accessibility access is missing.
- General also has "Open at login", the state of the Accessibility access, the
  [updates](#updates) and the [settings file](#settings-file).
- Scrollio stops while the Mac sleeps or another user has it, and starts again when you
  are back.
- When its event handling starts (at launch once Accessibility access is there, on
  Resume) and whenever Mos starts later while it runs, Scrollio quits a running Mos and
  says so with a notice: two apps would both handle the same mouse events. While Scrollio
  is paused or still waits for the access, Mos is left running. Mos's settings are not
  read.
- Scrollio's notices stay on screen as long as their text takes to read (3 to 10
  seconds) and wait while the pointer is over them.

## Settings file

General › Settings file saves all your settings to one file and loads them from one: to
move to another Mac, to keep a copy, or to pass a setup on.

- "Export…" writes one JSON file ("Scrollio Settings 2026-11-12.json") that any text
  editor opens. It holds what you set in Scrollio's panes: the scroll settings and the
  thumb wheel, the buttons and keys with their actions, the gestures, the apps with
  their own settings and "Change scrolling only in these apps", the Logitech values, and
  "Show in menu bar".
- It does not hold, and an import never changes: "Let Scrollio manage this mouse" (it
  stays as it is on each Mac: the Logitech values of a file are imported, but they are
  written to a mouse only where that switch is on), "Open at login", the Welcome Guide's
  progress, the update switches, and the two macOS settings of the Mouse pane
  ("Tracking speed" and "Pointer acceleration" are macOS's own).
- What Scrollio asks of a Logitech mouse whatever that switch says (see
  [Logitech MX mice](#logitech-mx-mice)) follows the imported settings as it follows
  yours: a Logitech button that has an action in the file is asked of the mouse, and a
  Logitech action of the file runs on the mouse when its button, key or gesture is used.
- "Import…" reads a file and shows what it holds before anything changes: which
  settings, how many apps, and every button and key with what it will do, in the words
  of the Buttons pane, with the gesture directions whose action is not the default
  one. For buttons and keys that open an app or a file, or run a script, a box of its
  own lists each one's whole path and arguments. Read those lists when the file is not
  your own: an action starts at a press of its button. Unless the file gives no button
  or key an action and leaves the gestures as they are by default, Return presses
  "Cancel". Importing itself starts nothing.
- An import replaces the kinds of settings the file holds and leaves the others as they
  are; a file made by "Export…" holds them all. The new settings are in effect at once.
- The settings from before each import are kept, the last five (the same settings
  never twice), as settings files named by their time (UTC) in
  `~/Library/Application Support/com.nikklemenc.Scrollio/Settings Backups`.
  "Restore…" appears under the row and opens that folder: the one you choose comes
  back through the same sheet.
- A file that is not a Scrollio settings file, is damaged, is larger than 2 MB, holds
  more than 1000 buttons and keys or 1000 apps, or was saved in a newer format than
  this version reads, changes nothing; the sheet says which.
- From a file that is read, an import takes only what this version understands:
  entries it cannot read and actions it does not run are left out, and numbers of
  Scrolling outside what the panes can set are corrected; the sheet says how many of
  each.
  That also holds for "Restore…": entries a newer version of Scrollio had stored (if
  you went back to an older version) are not kept by an import and do not come back.

## Updates

A released Scrollio (the one from the disk image) updates itself, with
[Sparkle](https://sparkle-project.org). Version 1.0.0 cannot do this yet: from 1.0.0,
get the next version by hand, once.

- On its second launch Scrollio asks once whether it may check for updates
  automatically. Afterwards the answer is two switches under General › Updates: "Check
  for updates automatically" (once a day) and "Install updates automatically" (a new
  version is downloaded in the background and installed the next time Scrollio quits,
  for example when the Mac restarts). "Check Now" there, and "Check for Updates…" in
  the menu bar menu and in the Scrollio menu, ask at once; when there is nothing newer,
  or the check failed, the alert every Mac app shows says so ("You're up to date!",
  with OK), in front and on the Space you are in. Scrollio goes on working behind it.
- When a check you asked for finds a version, a window says what is new and offers to
  install it. It opens where you are, over a full-screen app too, and so do the
  download and "Ready to Install" after it. If you leave it unanswered and go
  elsewhere, Scrollio sits in the Dock until you answer, so that ⌘Tab and the Dock find
  the window again.
- When the daily check finds a version, no window opens and nothing comes to the front:
  Scrollio goes into the Dock with a badge, its menu bar menu starts with "Update to
  Scrollio …" and General names the version. The window opens when you come to Scrollio
  (its Dock icon, ⌘Tab, its settings) or choose that menu item, which opens it where
  you are.
- An update is installed only when its disk image carries a signature made with
  Scrollio's update key (or, should that key ever be replaced, the signature of the
  same Developer ID as the installed app), and that is checked before the image is
  opened. The app in it is signed with that Developer ID and notarized, like the
  download. macOS keeps the Accessibility permission across an update.
- A check asks GitHub for one small file that names the newest version. What that
  request shows is under [Privacy](privacy.md#privacy).
- A copy built from source does not update itself and asks nobody; neither does a copy
  that runs from the disk image. General › Updates says so.
