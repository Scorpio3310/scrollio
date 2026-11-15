# Changelog

What changed in each released version of Scrollio, newest first.

The part under a version's heading is what the update window shows to people who have an
older version, and what the GitHub release says: `scripts/release.sh` reads it. So write
it for the people who use the app, and give the version its part before you tag it.
`## Unreleased` collects what the next version brings; it becomes that version's part
(the heading gets the version) before the tag.

## Unreleased

**Every app gets its own:** buttons, gestures and a Shortcut Ring for each app, with
suggested shortcuts for 100 of them.

### New

- **Buttons for each app.** In Apps, give any button, or the thumb wheel, something else to
  do in one app; every other button does what Buttons says.
- **Gestures and a Shortcut Ring for each app.** Safari › Gestures and Safari › Shortcut
  Ring give the app its own directions and its own eight shortcuts.
- **Suggested shortcuts for 100 apps.** Turn off "Use settings from Shortcut Ring" for Figma,
  Photoshop, Safari, Word, Discord, Zed and many more, and the app's ring starts with its
  most used shortcuts. They follow your keyboard layout.
- **Name your shortcuts.** A key combination you record can have a name and an icon. A
  gesture direction can send one too.
- **Scrolling in an app is one choice:** Same as Scrolling, Own Settings or Left to macOS.
- **Choose the button where you use it.** Gestures and Shortcut Ring list your mouse's
  buttons, record one in place and draw it on your mouse.
- **Edit the ring where you see it.** Click a place in the ring's drawing to set it; a
  secondary click swaps two places or clears one.
- **Thumb wheel.** Each action has its own Speed and "Reverse direction"; your one speed
  stays every action's until you move a slider. Switch Desktops can follow the wheel like
  a trackpad swipe: a long roll moves several desktops, each sliding in before the next.
- **Pause For** 15 minutes or an hour, in the menu bar: Scrollio starts again by itself.
- **The menu bar menu says when Scrollio is not working**, with the way out under it;
  General says the same. "Settings for Safari…" opens the page of the app you are in.
- **Undo.** Edit › Undo takes back a changed action, name or icon in Buttons, Gestures and
  Shortcut Ring, and shows where.
- **"Default" says what the button does:** "Default (Back)", "Default (Switch Wheel Mode)".
  Menus tick the action in use.
- **See which apps differ.** Scrolling, Buttons, Gestures and Shortcut Ring end with a line
  such as "Different in Safari and Figma"; click a name to go there.
- **A View menu.** ⌘1 to ⌘7 open Scrolling, Buttons, Gestures, Shortcut Ring, Mouse, Apps
  and General; ⌘[ and ⌘] go back and forward.
- **Mouse starts with your mouse;** "All mice (macOS)" comes last. Restore… in General
  lists the kept settings by date.
- **A new installation** starts the wheel in the classic direction, with Natural scrolling
  on or off. Your settings keep theirs.
- **The settings file holds all of this.** Going back to 1.0.5 drops names, icons and an
  app's own gestures, ring and thumb wheel: export your settings first.

### Fixed

- **Switch Desktops on the thumb wheel** moves a desktop every few notches and goes on when
  you take the wheel again; a stray tick or two does nothing, and Back and Forward takes a
  hard flick as one page.
- **A click while you hold the ring's button** runs the lit shortcut and no longer reaches
  the app under the ring.
- **Middle, Back and Forward of a Logitech mouse** set up on its receiver work over
  Bluetooth too.
- **The screen no longer goes a shade darker** while the Shortcut Ring is open.
- **A Logitech button with a modifier key** (⌥ + the mode shift button) runs its own
  action, no longer the plain button's (SmartShift); and a button kept for such a shortcut
  (⌘ + Back) still works when pressed alone.
- **Safari added with "Choose in Finder…"** now gets its own settings.
- **"Freeze pointer during a gesture"** reads on, dimmed, while the mouse itself keeps the
  pointer still.

## 1.0.5

**The Shortcut Ring arrives:** eight shortcuts around your pointer, one button away.

### New

- **Shortcut Ring.** Hold a button and a ring of eight shortcuts opens around the pointer.
  Move towards one and let go, or press once and click.
- **Any button opens it:** a mouse button, a Logitech button such as the MX Master 4's
  thumb panel, or a key combination. Set it up in the new Shortcut Ring pane.
- **Each place is yours:** a listed shortcut, a key combination you record, or an app or
  a file to open.
- **Liquid Glass** on macOS 26 and later.
- **MX Anywhere 3 / 3S and MX Vertical** have their own drawings and button lists in
  Settings. *Not yet tried on the mice themselves.*
- **Reset to Defaults** in Shortcut Ring and Gestures, with a few seconds to undo.

### Fixed

- **Mission Control and Show Desktop** no longer stop working after a while.
- **Mice on a Logitech receiver** are found when they connect after Scrollio has started.
- **Calendar** is no longer added to your list of apps. If 1.0.4 added it, remove it in
  Settings › Apps; it stays away.
- Sidebar symbols in Settings are centred.

## 1.0.4

- **The MX Master 4 is drawn as it is.** Its picture in Settings is redrawn from above,
  and has a second view from the thumb side: the thumb wheel on top, Forward and Back in a
  row under it, the gesture button in front of them and the thumb panel beneath. The
  picture turns to that side when you point at one of those in Buttons or Mouse, and for
  the hold in Gestures, and the rows' small pictures show the same side.
- **So is the MX Master 3** (3S, 3 for Mac): redrawn from above, with the same second
  view from the thumb side: the thumb wheel on top, Forward and Back in a row under it,
  and the thumb rest beneath. Its gesture button is the thumb rest itself, pressed
  down: it lights from above, in the middle of the wing.
- **Scroll slower**: a fourth key under Scrolling › While you hold a key, for fine work.
  While you hold it the wheel moves the page a fifth as far, as smoothly as ever. It has
  no key until you record one (⌥, ⇧ and ⌘ belong to the other three); a mouse button can
  hold it too ("Scroll Slower" in the Buttons pane), and an app with its own scroll
  settings has its own key.
- **Calendar is no longer smoothed** unless you say so. Its month view aligns itself to
  weeks and took a smoothed wheel badly: a small turn barely moved it and a little more
  ran away. If you update, Calendar appears once in Settings › Apps as an app with its
  own settings and Smooth scrolling off; the wheel's direction stays as it is. To have it
  as before, turn "Use settings from Scrolling" on for it or remove it from the list:
  Scrollio does not add it again. Nothing changes if Calendar is on your list already, or
  while "Change scrolling only in these apps" is on.
- Settings › Apps: an app's own page has a back button in the title bar, beside the
  app's name, as in System Settings. The "‹ Apps" link at the top of the page is gone.

## 1.0.3

- **About Scrollio** now opens the About window every Mac app has: the icon, the version,
  what Scrollio is, where it lives and the copyright. Before, it opened Settings on
  General; the same lines are still on top of General.

## 1.0.2

- **Trackpad-style scrolling is now Experimental** (it was Beta) and says where it works.
  While it is on, two switches show under it: "In browsers" (on) and "In Mac apps" (off
  until you turn it on). It is right in browsers and in Finder and uneven elsewhere: in
  some apps scrolling can stutter, stop short or not bounce. If you had it on in 1.0.1,
  Mac apps now scroll as without it until you turn "In Mac apps" on.
- In browsers: Safari now bounces at the ends of a page as Chrome does (macOS 27 and
  later; on older systems Safari stays as it was). Firefox and the apps built on its
  engine get the same (new and less tried). In Dia and Arc the sidebar of tabs scrolls
  its whole way again.
- In Mac apps: a list or a document bounces at its end as it does under a trackpad,
  instead of staying stretched while the wheel turns. For that Scrollio reads, through
  the Accessibility access it already has, the position of the scroll bar or of the
  content under the pointer, and nothing else. Where it can read neither, the app scrolls
  as without the switch. Good in Finder; uneven in some apps (Messages).
- With it on, scrolling sideways (Shift, "Scroll sideways", the thumb wheel) stays as it
  is without it, and Maps, Find My, Calendar, iPhone Mirroring, Blender and the Godot
  editor are left alone, so that the wheel keeps doing there what a wheel does.
- "You're up to date!" and a failed check are now the alert every Mac app shows. The
  window of an update you asked for opens where you are, also over a full-screen app. An
  update that the daily check finds no longer opens a window by itself: Scrollio shows
  its Dock icon with a badge, and the window when you come to it.
- On macOS 26 the line between the sidebar and the settings in the Settings window is
  gone.
- The purple of the app's switches, selection and buttons is a little darker.
- A new install starts at Speed 6.5, a tick of the slider (it was 6.3). If you never
  changed a scroll setting, a click now goes 3 % further; set Speed to 6.3 to have it as
  before.
- Mouse › Pointer speed: the slider has a step every 200 DPI from 400 to 4000.
- The settings file carries the two new switches.
- The disk image opens as a window that shows what to do: Scrollio's icon, an arrow and
  the Applications folder.

## 1.0.1

- **Scrollio updates itself.** If you allow it, Scrollio asks GitHub once a day whether
  there is a newer version, shows what is new and installs it. General has the two
  switches and "Check Now"; "Check for Updates…" is in the menu bar menu and in the
  Scrollio menu.
- An update is installed only when it carries the author's signature; a download that
  does not is never opened.
- This is the first version that can update itself: from 1.0.0, download this one by hand.
- **Your settings in a file.** General › Settings file: "Export…" saves all your
  settings to one file, and "Import…" loads them from one, on this Mac or on another.
- Before an import Scrollio shows what the file holds, with everything its buttons,
  keys and gestures would do and every app, file or script they would open or run, and
  asks. Your settings from before each import are kept, the last five: "Restore…"
  brings one back.
- "Let Scrollio manage this mouse" and "Open at login" are not in a file: they stay as
  they are on each Mac.
- On macOS 26 and later the sidebar of the Settings window is grey again, not white.

## 1.0.0

First public release: smooth, trackpad-like scrolling for any mouse, actions for mouse
buttons and keys, mouse gestures, thumb wheel actions, and settings for Logitech MX mice.
