# Uninstalling and diagnostics

## Uninstall

1. Quit Scrollio: "Quit Scrollio" in its menu bar menu, or ⌘Q while its Settings window is
   in front. Quitting gives a Logitech mouse its buttons back.
2. Move Scrollio from the Applications folder to the Trash.
3. In System Settings › Privacy & Security › Accessibility, select Scrollio and remove it
   with the minus button. In System Settings › General › Login Items, remove Scrollio if
   it is listed.
4. Delete its settings:

   ```bash
   defaults delete com.nikklemenc.Scrollio
   defaults delete com.nikklemenc.Scrollio.toast
   ```

5. Delete what the updater kept: a downloaded update, and what macOS stores for the
   app's web requests.

   ```bash
   rm -rf ~/Library/Caches/com.nikklemenc.Scrollio ~/Library/HTTPStorages/com.nikklemenc.Scrollio
   ```

6. Delete the settings from before an import, if you ever imported a settings file (the
   folder is only there then). Settings files you exported are where you saved them.

   ```bash
   rm -rf ~/Library/Application\ Support/com.nikklemenc.Scrollio
   ```

What stays, because it was never Scrollio's to keep:

- Values written to a Logitech mouse (pointer speed, wheel mode, haptics and so on)
  are stored in the mouse. Change them with Logi Options+, or with Scrollio before you
  remove it.
- "Tracking speed" and "Pointer acceleration" are macOS settings: System Settings › Mouse.

## Diagnostics

Scrollio writes what it did to the macOS system log, subsystem `com.nikklemenc.Scrollio`
(`com.nikklemenc.Scrollio.debug` for the debug build), in three categories. They stay
small: no line is written per wheel or pointer event, and no line says which key was
pressed.

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
  scroll: 5 wheel events 2140 px in -> 83 frames 2134 px out (largest 94), wheel 44 ms,
  glide after the last event 1389 ms, Duration 4.50 (tau 230 ms), trackpad-style off, ended: glided out
  ```

  `trackpad-style` says in which form the scroll was sent: `off`; `on (flick: 1 touches,
  2 wheel events into a glide)` for an app built on Chromium or on Firefox's engine; `on
  (one touch: 1 touches)` for any other app; `off (not sent to this app)` for Safari and
  the other apps that are left alone while the switch is on; `off (a sideways scroll)`
  for a sideways scroll while it is on.
  The line ends with why the scroll ended: glided out, left click, a finger on the
  trackpad, the wheel went on in another app, trackpad-style was switched, the wheel
  turned between up-down and sideways, the scroll tap was restarted, ended by the keeper,
  the display link sent no frames, or stopped. (With one touch a scroll's line comes a fifth of a second later than its
  last frame: the touch rests that long, and a turn of the wheel in that time is still
  the same scroll.) Also one `thumb wheel:` line per roll of
  the sideways wheel: what the wheel sent, the action and its speed, and the steps that
  ran (`1 step next, sent nothing` when the step's keys were not sent: "Move left a
  space" or "Move right a space" is switched off in System Settings). With Follow the
  wheel the line lists each swipe instead: how far it went, how it ended
  and how long the Space took to change, "late" when that was after the wait for it,
  "no change", or "stopped" when Scrollio stopped first; where no swipe could be made
  and the desktops went in steps, the steps. A roll's line is written once its steps
  ran and its swipes ended, so with Follow the wheel it can come up to three seconds
  after the roll, and after a later roll's line. For any action the line ends with the
  stray ticks it held and dropped. A copy you built yourself with `scripts/install.sh`,
  and the debug build, follow it with a `thumb wheel trace:` line for a roll that runs
  an action (each event's gap in ms and its lines, 128 at most; the wheel is tuned from
  it, and a released copy never writes it). Also at
  most one line per reason every 3 seconds while wheel events are let through unsmoothed
  (trackpad events, a remote desktop, smoothing off for that event or that axis, no
  display link, a display link that sends no frames, no right to post events, a Step or
  Speed that is not a number).
- `logi`: what a Logitech mouse reported (battery, pointer speed, haptics, press force,
  wheel settings), each decision to write a value or not and why, the read-back after a
  write, requests the mouse refused or did not answer, gesture haptic cues, and slow
  writes. A button the mouse did not take for Scrollio three checks in a row gets one
  line (`Button 0x00C3 Gesture: the mouse did not take its divert 3 times in a row …`);
  it is asked for again at each check (Settings opens, the mouse connects) and does what
  it does without Scrollio until the mouse takes it. A gesture button that the mouse
  tracks itself writes one line per press
  (`raw XY: CID 0x01A0 released after 14 samples`). A mouse is named by its model, as the
  mouse reports it; never by a name you gave it in the Bluetooth settings. For a
  receiver: whether its connection reports were on or had to be switched on, what each
  of its six places answered when Scrollio started, where a mouse was found, and each
  time a device connects or disconnects:

  ```text
  [USB Receiver] Receiver connection reports: were off, switched on
  [USB Receiver] Receiver slots: connected: 2; not connected (asleep, off or out of range): 1; empty: 3, 4, 5, 6
  [USB Receiver] Receiver: mouse in slot 2
  [MX Master 3S slot 0x02] Disconnected (the receiver says so)
  ```
- `app`: Scrollio's own health: each start and stop with its cause (launch, sleep and
  wake, another user, Pause and a pause that ended by itself, Accessibility access lost
  or back, quit), event taps that
  could not be created or that macOS turned off, restarts, a display link that runs and
  sends no frames (at most one line every 10 seconds; the wheel then goes on unsmoothed
  until frames come again; after three new links in a row without a frame, one more line,
  and the menu bar and General say "Smooth scrolling is off: no display frames": quit and
  reopen Scrollio), macOS not letting Scrollio post events and letting it again (checked at
  each start and wake, every 5 seconds while Scrollio runs and when the Accessibility
  list changes; without it nothing is smoothed and shortcuts may not reach apps; pause
  or quit Scrollio before you remove it from that list), settings that could not be
  read or written, an app, a file or a script that could not be opened (never its name
  or path), a held action whose release never came, a scroll key let go at a wheel turn
  without its modifier (its release was not seen), each use of the Shortcut Ring ("opened
  by" a mouse button, a key or a button over HID++, and "the own ring of the app in
  front" when it was an app's own, never which app; "left open"; then "closed, nothing
  ran" or "closed, ran" with the shortcut's name, or for a key combination or an app
  only what kind of thing it was), each action a gesture runs (`Gestures: up ran
  missionControl`; "asked for" a Logitech action; "sent nothing" and why for an action
  that sent nothing, such as a Spaces action whose shortcut is off in System Settings;
  a key combination only as "a recorded key combination", never its
  keys or its name; ", the app in front has its own gestures" when the set was an app's
  own, never which app), one line for each hold whose Up or Down followed the hand
  ("Up and Down follow the hand too"), written when its last event went out
  (`Gestures: up followed the hand: missionControl, vertical +, began after 48 ms, 37
  updates, furthest 0.82, released at 0.74, 1.9/s: ended, expected to open`: the view by
  its action's name, or "leaving missionControl" for the move that puts Mission Control
  away; the Dock's motion and its sign; the time from the press to the first event; how
  many events went out; the furthest and the last position as a share of the whole
  view, and the hand's speed in whole views a second, all three counted the hand's way
  out; then how it ended: "ended" when the button came up, with "expected to open" or
  "expected to close" when Scrollio expects macOS to finish it, which is what the
  stronger pulse of the mouse goes by; "cancelled" when the hand was back at the start
  or heading back; "cancelled, a flick: ran once" for a quick flick that was let go
  before the view had moved a fifth of the way: the action ran once instead, and its
  own line follows; or "cancelled" with what took it back: no button-up, the mouse went
  away, Scrollio's event taps stopped, the screens changed, the displays went to sleep,
  the desktop in use changed, the Shortcut Ring opened, its swipe had been taken back),
  one line for a direction that could follow the hand and ran once instead, right
  before the line of its action (`Gestures: up did not follow the hand: missionControl,
  the Dock's gesture is off`; the other reasons: "not on this macOS", which is Show
  Desktop before macOS 27; "cannot post events"; "the wheel's swipe was running"; and
  "Scrollio had just opened Mission Control", or "Show Desktop": that direction opened
  the view with your hand and the same move closes it. Apps, which such a line would
  name by its action `appExpose`, gets none in a released copy: it simply runs once),
  one line for a swipe of the desktops that was taken back because the screens changed
  or the displays went to sleep (`Gestures: a swipe of the desktops was taken back (the
  screens changed)`; the desktops' swipe writes no other line),
  a line after a change of the settings when the count of apps
  with their own binding for a Logitech button, or of the buttons they take from the
  mouse or give back, is not what the last such line said, and at launch when an app has
  such a binding ("2 app(s) have their own binding for a Logitech button: 1 Logitech
  button(s) taken from the mouse and 0 given back while such an app is in front",
  counted over the list of apps whatever app is in front, never which app; switching
  apps writes no line; a Logitech button that Scrollio has and that is down when the app
  in front changes stays with Scrollio until it is up, but one held while the mouse
  handles it can be taken in the middle of its press: the app's own action may then run
  without a new press, or macOS may not get its release), a line at launch and after a
  change of the settings when the count of Logitech buttons whose hold the mouse tracks
  itself ("Let the mouse track the gesture"), or of the apps whose own bindings or
  gestures change which while they are in front, is not what the last such line said
  ("Gestures: the mouse tracks the hold of 1 Logitech button(s) itself; 1 app(s) change
  which by their own settings while in front", never which app; switching apps writes no line; a button
  that is down keeps its tracking until it is up), at launch which accent colour
  is in effect, at the first Mission Control or Show Desktop whether the Dock is asked for
  them directly or they are sent as key presses (a macOS without the call), a sent
  shortcut that left modifier keys set (once), for "Trackpad-style scrolling (Experimental)" whether the wheel's hardware event is
  taken off what an app is sent (once: at launch when the switch is on, in the Scrolling
  pane or for an app; else at the first scroll after you switch it on), what Safari gets
  and which form is under evaluation, and the updater: whether this copy updates itself, and one line per check
  with what it found:

  ```text
  Accent colour: the app's own (purple)
  Started (the Mac woke up): the event taps and the Logitech sessions run
  Updates: on, automatic checks on, automatic install off, feed at github.com
  Updates: a scheduled check found no newer version
  ```

The log you export from Logitech Diagnostics is more detailed than the `logi` category:
read it before you share it.
