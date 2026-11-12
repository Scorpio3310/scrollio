# Changelog

What changed in each released version of Scrollio, newest first.

The part under a version's heading is what the update window shows to people who have an
older version, and what the GitHub release says: `scripts/release.sh` reads it. So write
it for the people who use the app, and give the version its part before you tag it.
`## Unreleased` collects what the next version brings; it becomes that version's part
(the heading gets the version) before the tag.

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
