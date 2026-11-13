# Changelog

What changed in each released version of Scrollio, newest first.

The part under a version's heading is what the update window shows to people who have an
older version, and what the GitHub release says: `scripts/release.sh` reads it. So write
it for the people who use the app, and give the version its part before you tag it.
`## Unreleased` collects what the next version brings; it becomes that version's part
(the heading gets the version) before the tag.

## Unreleased

- **The MX Anywhere 3 and 3S and the MX Vertical have drawings of their own.** With one
  of them connected, Settings shows that mouse instead of a plain one, from above and
  from its thumb side, and Buttons lists its buttons in the order they sit on it: the
  wheel's click, the button behind the wheel (MX Anywhere) or the pointer speed button on
  the top (MX Vertical), then Forward and Back. The mouse is recognised by its name;
  there is nothing to set. Both were drawn and set up from Logitech's descriptions of
  these mice and have not been tried on the mice themselves yet.
- **The Shortcut Ring is drops now.** The disc behind the ring is gone: each of the eight
  places is a round drop of its own, with one more in the middle that names the shortcut
  you point at. When the ring opens, the drops come out of the middle one after the
  other and settle around the pointer; the one you point at grows and takes the accent
  colour. You can choose from the first moment, as before, and the ring still goes away
  at once. On macOS 26 and later the drops are Liquid Glass; on macOS 14 and 15 they are
  the blurred material the ring had. With Reduce transparency or Increase contrast they
  are drawn solid, and with Reduce motion the ring simply appears.
- **"Reset to Defaults" in Shortcut Ring and in Gestures.** Both panes now end with the
  button the Scrolling pane has. In Shortcut Ring it puts back the ring of a new
  installation, in Gestures the actions of the directions and of the click and the
  pane's other settings. The button or key that opens the ring, and the button you hold
  for a gesture, stay as they are. For a few seconds after a reset the button reads
  "Undo Reset" and takes it back; Edit › Undo does the same.
- **Calendar is no longer put on your list of apps.** Version 1.0.4 added Calendar to
  Settings › Apps by itself, with Smooth scrolling off. Scrollio no longer adds an app to
  that list: only you do. If 1.0.4 added Calendar on your Mac and you do not want it,
  select it in Settings › Apps and remove it; it does not come back. If Calendar's month
  view scrolls badly with a smoothed wheel, add Calendar there yourself and turn Smooth
  scrolling off.
- **Mission Control and Show Desktop no longer stop working.** Scrollio sent them as key
  presses, and after some orders of use (Show Desktop, then another shortcut) macOS only
  flashed them, for a button, a gesture and the Shortcut Ring alike, until you used a
  trackpad gesture or the key yourself. Scrollio now asks the Dock for them directly.
  Also, after a shortcut was sent, macOS could go on treating its modifier keys as held
  until your next key or click; that no longer happens.
- **A Logitech mouse on a receiver is found when it connects later.** Scrollio looked for
  mice on a Bolt or Unifying receiver once, when it started or the Mac woke up. A mouse
  that was asleep, switched off or out of range at that moment was not seen until you
  restarted Scrollio, unless Logi Options+ was running. Scrollio now asks the receiver to
  say when a device connects, and no longer gives up on a mouse because the receiver was
  busy with the keyboard next to it. A mouse you switch off and on gets its buttons back.
  The system log says what was found on the receiver (see "Uninstalling and diagnostics").
- **Shortcut Ring**: a ring of eight shortcuts that opens around the pointer, for any
  mouse. Give a mouse button, a Logitech button such as the MX Master 4's thumb panel, or
  a key combination the new action "Shortcut Ring" (Buttons, or "Set Up…" in the new
  Shortcut Ring pane). Hold it and move towards a shortcut, then let go; or press it and
  let go, and click a shortcut in the ring that stays open. The app you are in keeps the
  keyboard, so Copy and Paste go where you were. The pane sets what the eight places
  hold: a listed shortcut, a key combination you record, or an app or a file to open;
  a settings file carries it. If Logi Options+ manages your mouse, let a button
  send a keystroke there and record that keystroke as the ring's button. An MX Master 4
  whose thumb panel Scrollio reads pulses when a shortcut lights and when it runs. With
  "Freeze pointer while the ring is held" the pointer stays where it was while you hold
  the button.
- The symbols in the sidebar of the Settings window stand in the middle of their tiles,
  as in System Settings. They stood up to 0.75 pt low and 0.5 pt to the left.

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
