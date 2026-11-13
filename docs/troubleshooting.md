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
  or stopped. (With one touch a scroll's line comes a fifth of a second later than its
  last frame: the touch rests that long, and a turn of the wheel in that time is still
  the same scroll.) Also one `thumb wheel:` line per roll of
  the sideways wheel, and at
  most one line per reason every 3 seconds while wheel events are let through unsmoothed
  (trackpad events, a remote desktop, smoothing off for that event or that axis, no
  display link, a Step or Speed that is not a number).
- `logi`: what a Logitech mouse reported (battery, pointer speed, haptics, press force,
  wheel settings), each decision to write a value or not and why, the read-back after a
  write, requests the mouse refused or did not answer, gesture haptic cues, and slow
  writes. A gesture button that the mouse tracks itself writes one line per press
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
  wake, another user, Pause, Accessibility access lost or back, quit), event taps that
  could not be created or that macOS turned off, restarts, settings that could not be
  read or written, an app, a file or a script that could not be opened (never its name
  or path), a held action whose release never came, each use of the Shortcut Ring ("opened
  by" a mouse button, a key or a button over HID++; "left open"; then "closed, nothing
  ran" or "closed, ran" with the shortcut's name, or for a key combination or an app
  only what kind of thing it was), at launch which accent colour is
  in effect, for "Trackpad-style scrolling (Experimental)" whether the wheel's hardware event is
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
