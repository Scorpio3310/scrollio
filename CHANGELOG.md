# Changelog

What changed in each released version of Scrollio, newest first.

The part under a version's heading is what the update window shows to people who have an
older version, and what the GitHub release says: `scripts/release.sh` reads it. So write
it for the people who use the app, and give the version its part before you tag it.
`## Unreleased` collects what the next version brings; it becomes that version's part
(the heading gets the version) before the tag.

## Unreleased

### New

- **Buttons for each app.** In Apps, give any button, or the thumb wheel, something else
  to do in one app, the Shortcut Ring and Gesture Navigation too; every other button does
  what Buttons says.
- **Gestures for each app.** On an app's page in Apps, give the app its own action for
  each gesture direction and the click: they run in that app.
- **A Shortcut Ring for each app.** On an app's page in Apps, give the app eight shortcuts
  of its own: that ring opens in that app.
- **An app's page has everything Scrolling, Gestures and Shortcut Ring have.** The thumb
  wheel's speed and direction, the gestures' mode, swipe speed and switches, and the
  ring's "Freeze pointer" can be set for each app too.
- **Suggested shortcuts for 100 apps.** Turn off "Use settings from Shortcut Ring" for Figma,
  Photoshop, Safari, Word, Discord, Zed and many more, and the app's ring starts with
  its most used shortcuts, on your keyboard layout.
- **Name your shortcuts.** A key combination you record can have a name and an icon: the
  ring and Settings show them, with the keys smaller beside them.
- **Key combinations for gestures.** A gesture direction or its click can send a key
  combination you record, with a name and an icon, as a ring's place can.
- **Your button in the picture.** Gestures and Shortcut Ring draw the button or key that
  really runs them, on your mouse; with none yet, a dashed outline shows where it goes.
- **Quiet until it runs, and a way back per app.** Gestures and Shortcut Ring fold their
  settings while nothing runs them; Safari › Scrolling shows its settings only while
  Safari has its own, as Safari › Gestures and Safari › Shortcut Ring do; each of them
  has a button that puts it back.
- **Thumb wheel, your way round.** Each thumb wheel action has its own "Reverse
  direction", and Switch Desktops can follow the wheel like a trackpad swipe.
- **Pause for a while.** In the menu bar, "Pause For" under "Pause Scrollio" pauses
  Scrollio for 15 minutes or an hour; the menu and General say until when, and Scrollio
  starts again by itself.
- **Edit the ring where you see it.** Click a place in the Shortcut Ring's drawing to
  choose its shortcut right there; a secondary click swaps two places, names and icons
  included, or clears one.
- **See which apps differ.** Scrolling, Buttons, Gestures and Shortcut Ring each end with
  a line such as "Different in Safari and Figma"; click a name to open that app's page
  there.
- **A View menu for Settings.** ⌘1 to ⌘7 open Scrolling, Buttons, Gestures, Shortcut Ring,
  Mouse, Apps and General; Back (⌘[) and Forward (⌘]) go through the places you looked at.

### Changed

- **The wheel starts the right way round.** A new installation follows macOS's Natural
  scrolling, so the wheel starts in the classic direction on every Mac, and Reset to
  Defaults in Scrolling brings that direction back; your settings keep theirs.
- **The Scrolling preview moves the page the way your wheel does**, with Natural
  scrolling on or off.
- **The menu bar menu says when Scrollio is not working.** Paused, waiting for
  Accessibility or unable to start, its first line says so, with the way out under it; a
  click on a mouse's battery opens Settings › Mouse.
- **Choose the button where you use it.** Gestures and Shortcut Ring list your mouse's
  buttons, with what each does now, and record one in place: no trip to Buttons.
- **Undo for a button's action.** In Buttons and in Safari › Buttons, Edit › Undo takes
  back a changed action, name or "Which Button Is This?"; "−" sets your mouse's button
  back to Default.
- **An app's page says which button runs its gestures and ring.** Figma › Gestures and
  Figma › Shortcut Ring begin with that button ("Back button, only in Figma") and a
  button that goes there, or sets one up for that app only.
- **Apps says what each app has of its own.** "Own: scrolling and 2 buttons" in
  the list and on the app's page, where a dot marks each of them.
- **An app's buttons say what they do.** "Remove All Buttons", "Copy from Gestures",
  "Use Suggested Shortcuts" and "Copy from Scrolling" instead of "Reset to Defaults".
- **Suggested rings are easy to find.** Figma › Shortcut Ring offers its suggested
  shortcuts, and + in Apps marks the apps that have them.
- **A click while you hold the ring's button belongs to the ring.** It runs the shortcut
  that is lit (nothing lit: the ring closes), and nothing reaches the app under the ring.
  A click right as you press the button does nothing.
- **Scrolling in an app is one choice.** Safari › Scrolling asks "Scrolling in Safari":
  Same as Scrolling, Own Settings or Left to macOS (not smoothed, not reversed).
  Nothing you set changes; an app whose own settings already had both off reads Left to
  macOS.
- **"Default" means one thing.** Every button without an action says "Default", with what
  it then does where that is certain ("Default (Back)", "Default (Switch Wheel Mode)");
  Safari › Buttons says "In other apps: …" under each row, and each row's menu starts
  with "Same as Other Apps (…)", which gives the button back to Buttons.
- **One set of words.** Safari › Gestures and Safari › Shortcut Ring say "Use settings
  from Gestures" and "Use settings from Shortcut Ring", and their first line "…, as in
  other apps".
- **The Welcome Guide says where to go next.** Its last step leads on to Buttons, Gestures
  or the Shortcut Ring.
- **An app's own ring shows whose it is.** The app's icon sits faintly in the middle of its
  own Shortcut Ring until a place lights.
- **Record a Button… says what it replaces** ("Replaces: Copy"), and "Show in Buttons"
  selects the row it names.
- **Menus show what is set.** An action menu ticks the action in use (its group shows a
  dash), and every jump inside Settings reads "Show in …": Show in Gestures, Show in
  Scrolling, Show in Mouse, Show in Shortcut Ring, "Show in Safari › Gestures".
- **Undo for the ring's places and the gesture directions.** In Shortcut Ring, Gestures,
  Safari › Shortcut Ring and Safari › Gestures, Edit › Undo takes back a changed action,
  name or icon, and shows it: that place comes forward with the row selected. So does
  Undo in Buttons and Safari › Buttons, and of an app removed from Apps.
- **Pause from Settings.** The top of General always says whether Scrollio works, in the
  menu bar's words, with Pause (or Resume, Try Again Now, Open System Settings).
- **Restore by date.** Restore… in General lists the kept settings by date and time.
- **Settings for the app in front.** The menu bar menu has "Settings for Safari…": it
  opens that app's page in Apps, or offers "Add Safari" there.
- **Mouse starts with your mouse.** With a Logitech mouse, Mouse starts with "Let Scrollio
  manage this mouse" and that mouse's settings; "All mice (macOS)" comes last.
- **Freeze pointer says what really happens.** While "Let the mouse track the gesture"
  keeps the pointer still, "Freeze pointer during a gesture" reads on and is dimmed, with
  the reason.
- **A free Gesture button or Thumb panel says what it is good for** in Buttons ("Good for
  Gestures or the Shortcut Ring."), until a button does it.
- **Speeds read one way.** Scrolling, the thumb wheel and Gestures write a speed as "1.0×"
  or "1.25×".
- **The thumb wheel reaches the next desktop.** Switch Desktops moves a desktop every few
  notches of one roll (at most one each quarter second), Follow the wheel chains swipes so
  one long roll moves several desktops, and a single stray tick of the wheel does nothing.

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
