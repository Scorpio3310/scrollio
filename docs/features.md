# Buttons, gestures, the Shortcut Ring, the thumb wheel and the rest

What each part of Scrollio does, beyond scrolling. Scrolling itself, with
Trackpad-style scrolling (Experimental), is in [scrolling.md](scrolling.md).

## Buttons and keys

- The actions: a system shortcut (Mission Control and Spaces, apps and windows, editing,
  Finder, screenshots, navigation and more), a keyboard shortcut you record, a modifier
  key, another mouse button, one of the scroll keys, Gesture Navigation, the
  [Shortcut Ring](#shortcut-ring), or opening an app, a file or a script.
- The listed shortcuts (Select All, Undo, Copy and the rest) press the right key on every
  keyboard layout, and keys are named as your keyboard names them.
- To record a button or a key, click + and press it. Esc, a left click, closing the
  popover or switching to another app ends the recording.
- A keyboard shortcut you record ("Keyboard Shortcut…" in a row's menu) can have a name
  and an icon, since "⇧⌘R" does not say what it does. Once the keys are recorded, the
  same popover shows a small square for the icon beside a field for the name. A click on
  the square (or Space) opens the icons in a popover of their own: about 100 symbols in
  six groups, the common ones first, with a search over their names. One character or
  emoji typed into that search, or picked with "Emoji & Symbols…", is offered first.
  "Remove Icon" there, or Delete on the square, takes the icon away; Esc closes only the
  icons. Both are optional. "Done", Return or a click elsewhere closes the popover and
  keeps what you set. On a row that already has recorded keys, "Keyboard
  Shortcut…" opens the name and icon at once; "Record Again" there asks for other keys
  and keeps the name and the icon. The row then shows the icon and the name, and the
  keys after them in grey. A listed shortcut, an app to open and a mouse button have
  their own names and take none. The name and icon belong to that one button (or that
  one place of a ring, or that one direction of a gesture), not to the keys: the same
  keys can be called something else elsewhere. A name is one line of at most 24
  characters.
- Going back to version 1.0.5 keeps the recorded keys, but 1.0.5 knows nothing of names
  and icons, of an app's own gestures, of an app's own ring or of an app's own thumb
  wheel. It drops the names and icons the first time it saves the buttons, the ring or
  the gestures (a change in that pane, or an import), and every app's own gestures, ring
  and thumb wheel the first time it saves the list of apps (a change in the Apps pane,
  or "Smooth Scrolling in …" in the menu bar menu). Export…, Import… and Restore… in
  1.0.5 save every setting first, so they drop all of it at once, from the file Export…
  writes too. Coming back to this version does not bring them back: export your settings
  in this version before you go back, and importing that file here later does.
- A drawing of the mouse lights the button each row is about. The MX Master 4, the MX
  Master 3 and 3S, the MX Anywhere 3 and 3S and the MX Vertical each have a drawing of
  their own, from above and from their thumb side, where the side buttons are (on an MX
  Master also the thumb wheel and the thumb panel, or the gesture button in the thumb
  rest): the drawing turns to the side the row's button is on. Any other mouse is drawn
  as a plain one. With one of these mice, its buttons are listed in the order they sit
  on the mouse, and any other buttons and keys under them:
  - MX Master 4: Middle button, Mode shift button, Thumb wheel, Gesture button, Forward
    button, Back button, Thumb panel.
  - MX Master 3 and 3S: Middle button, Mode shift button, Thumb wheel, Forward button,
    Back button, Gesture button.
  - MX Anywhere 3 and 3S: Middle button, Mode shift button, Forward button, Back button.
  - MX Vertical: Middle button, Pointer speed button (the one on its top), Forward
    button, Back button.

  The MX Anywhere and the MX Vertical were drawn and set up from Logitech's descriptions
  of them; they have not been tried on the mice themselves yet.
- On a Logitech mouse, buttons that macOS does not report (such as the gesture button,
  the mode shift button and the thumb panel) can have actions too. With a Logitech mouse
  connected, a button, a key or a gesture can also run a Logitech action: switch the
  wheel mode, change the pointer speed, or switch the mouse to another computer.
- A row says when its button is also a scroll key, or when another app (Logi Options+)
  may take it over.
- Removing a button or an app can be undone (Edit › Undo).
- Buttons for one app: an app's page in Apps (add the app there, or open it in the list)
  has four parts, chosen at its top: Scrolling, Buttons, Gestures and Shortcut Ring; the page
  opens on the part you looked at last, for any app. In Buttons the app holds only the
  buttons that do something else in it, and every other button does what the Buttons
  pane says (as Logi Options+ does it). + offers the buttons of your mouse, "Record a
  Button or Key…" and the buttons the Buttons pane gives an action; a new row starts
  with the action it has everywhere, and the line under it says what that is. "Default"
  lets the button do what it does by itself in that app. − gives the button back to the
  Buttons pane. These rows count while the app is in front (the app in front, not the
  one under the pointer: the actions go to it); while Scrollio's own Settings are in
  front, every button does what Buttons says. Nothing stays general: + offers the button
  that opens the Shortcut Ring or runs Gesture Navigation in the Buttons pane too (such
  as the MX Master 4's thumb panel), and a row's menu is the Buttons pane's, the Shortcut
  Ring and Gesture Navigation among it ("Show Gesture Settings" opens the app's Gestures
  part). A button that opens the ring while the app is in front opens the app's own ring
  if it has one, else the general one; one that runs Gesture Navigation runs the app's
  own gestures if it has them, else the general ones. A Logitech
  button that no binding of the Buttons pane uses is taken from the mouse only while an
  app that gives it an action is in front, and is the mouse's own again in every other
  app. In the list of apps, small marks say what an app has of its own (scrolling
  settings, buttons, gestures, a ring); a click on one opens the page on that part.
  While "Change scrolling only in these apps" is on, every app on the list has its
  scrolling changed, also one you added only for its buttons, gestures or ring, and its
  page says so under the app's box: to leave its scrolling to macOS, turn off "Use
  settings from Scrolling" on its page and, in its own settings, "Smooth scrolling" and
  "Reverse wheel direction".
- "Reset to Defaults" under an app's Buttons part removes all of the app's own buttons
  and its own thumb wheel action at once: every button does what the Buttons pane says
  again. It can be clicked while the app has something of its own; for a few seconds it
  reads "Undo Reset", and Edit › Undo brings everything back, also after the page closed.

## Mouse gestures

- Hold the button that has the action Gesture Navigation and move the mouse: up, down,
  left and right each run an action, and letting go without moving runs one more.
- Each of the five takes one of the listed actions, or a key combination you record
  there ("Keyboard Shortcut…"), with a name and an icon if you like, as a button's (see
  [Buttons and keys](#buttons-and-keys)). It is sent as a place of the Shortcut Ring
  sends it; the recorder takes what a place takes (a key combination, or the Back or
  Forward button, which is the Back or Forward click). The preview shows its icon, or
  else its keys. Version 1.0.5 and older shows such a direction as "No Action" and runs
  nothing for it (what going back to 1.0.5 drops: [Buttons and keys](#buttons-and-keys)).
- Two modes: "One action per hold", and "Follow the hand", in which moving sideways
  slides the desktops with your hand, like a trackpad swipe. "Follow the hand" uses a
  private macOS interface; where it is missing, the mode is not available.
- "Freeze pointer during a gesture" keeps the pointer where it is while you hold the
  button.
- An app can have gestures of its own. Its page in Apps (add the app there, or open it
  in the list) has a "Gestures" part. "Use the general gestures" is on for every app;
  turn it off and the app gets everything of the Gestures pane but the button to hold,
  in the pane's order: the mode, the five directions, "Invert left and right", "Freeze
  pointer", the swipe speed and, while a connected mouse can do them, the two switches
  of a Logitech mouse. They start as a copy of the pane's at that moment and are set the
  same way ("Keyboard Shortcut…" with a name and an icon too). They run while the app is
  in front when you press the button (the app in front, not the one under the pointer:
  the actions go to it); the gesture keeps them until you let go, whatever comes to the
  front meanwhile. While Scrollio's own Settings are in front, the pane's gestures run.
  Whether the mouse tracks a button's hold itself follows the app in front too (a button
  that is down keeps what it had until it is up). In "Follow the hand" (the app's own
  mode) Left and Right on the app's page say so, as in the pane. The button to hold is
  the Buttons pane's, unless the app's Buttons part gives it another action or gives
  another button Gesture Navigation: the app's Gestures part then names the button to
  hold there, or says that none runs the gestures. While only an app's own button runs
  Gesture Navigation, the Gestures pane says in which apps and with which button, and
  its "Change" shows that app's Buttons part. "Reset to Defaults" under the app's
  gestures puts them back to a copy of the pane's as they are then (all of them, the
  actions with their names and icons too); the switch stays off, and Edit › Undo takes
  it back. While no button runs Gesture Navigation with the app in front, "Directions",
  "Behavior" and "Logitech mouse" fold the app's gestures away, as in the pane: a click
  on one opens it. Turn the switch on again and the app's gestures are kept for later.
  An app added for its gestures has its scrolling changed too while "Change scrolling
  only in these apps" is on, as one added for its buttons (see [Buttons and
  keys](#buttons-and-keys)).
- With a Logitech MX Master, the mouse can track the gesture itself (Beta), and an MX
  Master 4 can pulse when a gesture locks in.
- "Reset to Defaults" at the bottom of the Gestures pane puts every gesture setting back
  to what a new installation has: the mode, the action of each direction and of the
  click, and the pane's switches and swipe speed. The button to hold stays as it is. The
  reset can be taken back: for a few seconds the button reads "Undo Reset" (Edit › Undo
  does the same).
- While no button runs Gesture Navigation, the Gestures pane folds the settings under
  the button's box under their titles: a click on a title opens them, and everything
  can be set. Once a button runs it, they show as usual.

## Shortcut Ring

A ring of eight shortcuts that opens around the pointer, for any mouse. Give a mouse
button, a Logitech button such as the MX Master 4's thumb panel, or a key combination
the action "Shortcut Ring" (in Buttons, or with "Set Up…" in the Shortcut Ring pane);
nothing opens the ring until you do. A button or key of an app's own can open it too,
only while that app is in front: while nothing else does, the pane says in which apps
and with what, and its "Change" shows that app's Buttons part. The pane also sets what
the eight places hold.

- Two ways to choose, both always there:
  - Hold: press and hold the button, move the mouse towards a shortcut (it lights by
    the direction of your hand, you need not land on it), and let go. The shortcut
    runs. Back in the middle and let go: the ring closes and nothing runs.
    While you hold the button a click is the ring's, never the app's under it: the lit
    shortcut runs when the click comes up (nothing lit, or another mouse button: the
    ring closes and nothing runs); a click right as you press the button does nothing.
  - Click: press the button and let go without moving. The ring stays open: point at a
    shortcut and click it. A click anywhere else (an empty place too), Esc, the button
    again, or ten seconds without moving the pointer close the ring; nothing runs.
- Letting go with a shortcut lit runs it; letting go with nothing lit leaves the ring
  open, however long you pressed. Right after the press a shortcut lights only after a
  longer movement, so that the press itself does not choose.
- The ring never takes the keyboard: the app you are in stays in front, so Copy, Paste
  and the other shortcuts go to it. The ring is gone before its shortcut runs (a
  screenshot does not show it).
- It opens on the display the pointer is on, over full-screen apps and on every Space.
  Near the edge of a screen the whole ring stays visible, a little away from the
  pointer, and while you hold the button it is still the direction of your hand that
  chooses.
- "Freeze pointer while the ring is held" (off for a new ring) keeps the pointer where
  it was while you hold the button, as the same switch of Gestures does for a gesture:
  the direction of your hand chooses, and the pointer is where you left it when the
  shortcut runs. A ring that stays open always has a free pointer, for the click.
- A place holds what a button can: one of the listed keyboard shortcuts (Mission Control
  and Spaces, apps and windows, editing, Finder, system, screenshots, navigation), the
  Back or Forward click, a key combination you record ("Keyboard Shortcut…"), or an
  app, a file or a script to open ("Open App or File…"); or nothing. An app shows its
  icon in the ring, a key combination its keys, and the drop in the middle of the ring
  names what is lit. A key combination with a name and an icon (see
  [Buttons and keys](#buttons-and-keys)) shows the icon in its drop, and in the middle
  the name with the keys under it, smaller; with only a name its drop keeps the keys,
  with only an icon the middle shows the keys. In an app's own ring the same keys can
  have another name. An empty place is a small faint drop. A new ring has Mission Control on top and Apps at the bottom, the
  desktops on the left and right, Copy and Paste beside Apps, and a screenshot of a
  selection and Show Desktop beside Mission Control.
- An app can have a ring of its own. Its page in Apps (add the app there, or open it in
  the list) has a "Shortcut Ring" part. "Use the general ring" is on for every app; turn
  it off and the app gets eight places of its own and its own "Freeze pointer while the
  ring is held", which start as a copy of the ring as it is at that moment and are set
  like the pane's. That ring opens while the app is in front (the app in front, not the
  one under the pointer: the shortcuts go to it); while Scrollio's own Settings are in
  front, the general ring opens. The ring that opened stays until it closes, with its
  freeze switch. What opens the ring is set in the Buttons pane, or for one app in its
  Buttons part: a button or key can open the ring only in that app, or do something else
  there; while nothing opens the ring with the app in front, the app's page says so, and
  "Shortcuts" folds the app's ring away (a click on it opens it). "Reset to Defaults"
  under the app's ring puts it back where it started (its suggested shortcuts, see
  below, else a copy of the general ring as it is then, and the general ring's freeze
  switch as it is then); the switch stays off, and Edit › Undo takes it back. Turn the
  switch on again and the app's ring is kept for later. An app added for its ring has
  its scrolling changed too while "Change scrolling only in these apps" is on, as one
  added for its buttons (see [Buttons and keys](#buttons-and-keys)).
- Scrollio suggests shortcuts for 100 popular apps (Figma, Photoshop, Final Cut Pro,
  Safari, Word, Xcode, Discord, Zed, GitHub Desktop …: each app's most used ones, Undo
  and Redo on the left and right, zoom on top and bottom, Copy and Paste below). Nothing
  changes by itself: only when you turn "Use the general ring" off for such an app does
  its ring start with them instead of the copy, and while its own ring is in use,
  "Reset to Defaults" under it puts them in all eight places again (Edit › Undo takes
  that back); the page says whether the ring started from them. They are ordinary
  places afterwards: change any of them. No suggested place deletes what cannot be
  brought back or changes something outside the Mac at one flick (a git app fetches
  rather than pushes), and a place whose key the app does not document stays empty. The keys are those of your keyboard layout at
  that moment (on a German or Slovenian keyboard ⌘Z is still Undo and zoom is the + and
  − keys); a shortcut whose key your layout types only with Option ("[" on those
  layouts) takes Scrollio's own Back or Forward in a browser, or other keys the app has
  for it, and else its place stays empty (the page says how many). So does a shortcut
  that would be ⌘ or ⇧⌘ with the key beside the left Shift, which switches windows
  there (⌘<): zoom in Notes, Pages, Keynote, Numbers and TextEdit, and Excel's font
  size. Mail's arrow and
  Delete keys are not suggested (they would type into a text field); where other apps
  zoom out, Outlook's place stays empty rather than Delete, and Excel gets its font
  size.
- "Reset to Defaults" at the bottom of the Shortcut Ring pane puts that new ring back:
  its eight places, and "Freeze pointer while the ring is held" off. The button or key
  that opens the ring stays as it is. The reset can be taken back: for a few seconds
  the button reads "Undo Reset" (Edit › Undo does the same).
- While nothing opens the ring, the Shortcut Ring pane folds its shortcuts under their
  title ("Shortcuts"): a click on it opens them, and everything can be set. Once a button
  or key opens the ring, they show as usual.
- How it looks: nine round drops and nothing behind them, one for each place and one in
  the middle. When the ring opens, the places' drops leave the middle one after the
  other, clockwise from the top, and are in their places after a third of a second; you
  need not wait for them, the ring chooses from the first moment. The drop of the
  shortcut you point at grows, moves a little outwards and takes the accent colour. The
  ring goes away at once.
  - On macOS 26 and later the drops are Liquid Glass: they flow out of one drop as the
    ring opens.
  - On macOS 14 and 15 they are the blurred material the system uses for its own
    panels. The movement is the same.
  - With "Reduce transparency" or "Increase contrast" (System Settings › Accessibility ›
    Display) the drops are drawn solid, with a firm outline for Increase contrast.
  - With "Reduce motion" the ring simply appears with every drop in its place, and a
    drop lights without growing gradually.
- With Logi Options+: if Logi Options+ manages your mouse, give the button there a
  keystroke (for example ⌃⌥Space), and record the same keystroke in Scrollio as the
  ring's button ("Set Up…" in the Shortcut Ring pane, then press that button). The
  ring then opens when you press the button and stays open for a click; if Options+
  holds the key while you hold the button, moving and letting go works as well. Use a
  key combination that no app needs.
- On a mouse with a haptic motor whose button Scrollio reads itself (an MX Master 4's
  thumb panel bound in Scrollio), the mouse pulses lightly when a shortcut lights and
  more firmly when one runs. "Haptic feedback" in the Gestures pane is the switch for
  these pulses too. A button that reaches Scrollio as a keystroke gets no pulse.
- The ring is a pointer tool: it cannot be reached with the keyboard or with VoiceOver's
  keys (VoiceOver is told the name of the shortcut that lights). Everything a place can
  hold can also be given to a button or a key directly.
- Not in a place: the left, right and middle click (they would click where your hand
  ended up), the modifier keys and the scroll keys (they only mean something while
  held), Gesture Navigation, the Logitech actions and the ring itself.
- Not in this version: rings inside rings; your own symbols; more or fewer than eight
  places; an app's icon in the middle of its ring; a step of the Welcome Guide.

## Thumb wheel

The sideways wheel (an MX Master's thumb wheel, or a wheel that tilts) has its own
settings, under Scrolling › Thumb wheel and, with an MX Master, in the Thumb wheel row of
the Buttons pane. They apply to every app, unless an app has settings of its own for the
wheel.

- Action: Scroll Sideways (the default), Zoom, Switch Tabs, Switch Desktops, Back and
  Forward, or Volume.
- Speed, and Swap direction.
- An app can have all three of its own, on its page in Apps, where the wheel is the
  same as in the panes: the Scrolling part has the Thumb wheel box, and the Buttons part
  a Thumb wheel row whose action is the box's action. Its settings count while the app
  is in front (not the one under the pointer: the keys of Zoom, Switch Tabs and Back and
  Forward go to it); a turn keeps them until the wheel rests, whatever comes to the
  front meanwhile. While Scrollio's own Settings are in front, the wheel does what the
  panes say.
- Speed and Swap direction are scroll settings of the app: they are its own while "Use
  settings from Scrolling" is off on its page (they start as what the wheel did in the
  app at that moment, and stay for later while the switch is on). The Scrolling part
  shows its settings, the Thumb wheel box among them, only while that switch is off: on,
  it is the switch alone, as the Gestures and Shortcut Ring parts are with theirs. An
  app whose own settings date from before keeps the speed and direction of Scrolling ›
  Thumb wheel until you change them on its page.
- The action is the app's own whatever that switch says: choose it in the Scrolling
  part's box while the switch is off, or, either way, with "+" of the Buttons part, which
  offers "Thumb wheel" while the connected mouse has one (an MX Master 4, 3 or 3S). The
  new row starts with what the wheel does everywhere. Without a speed of its own, an
  app's action runs at the default speed when it is of the other kind than what the
  wheel does everywhere (scrolling against steps). "−" gives the action back to Buttons;
  Edit › Undo takes it again.
- "Reset to Defaults" of the app's Scrolling part (there while the switch is off) gives
  the wheel 1× and no swap there and the action of every app again; that of its Buttons
  part takes the action away.

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
- The pulse of a gesture or of the Shortcut Ring plays on the mouse and can switch its
  haptics on, unless Haptic feedback is turned off.

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
  thumb wheel, the buttons and keys with their actions, the gestures, what the
  Shortcut Ring holds, the apps with their own settings (an app's own buttons, gestures and ring among them) and "Change scrolling only in these apps", the Logitech values, and
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
  of the Buttons pane, with the gesture directions and the places of the Shortcut Ring
  (and of each app's own gestures and ring) whose action is not the default one, and
  each app's own thumb wheel action; an app's own gestures in use with only the default
  actions, or with left and right swapped, have a line too. What is an app's own is named with the app (by its file,
  where it runs). A recorded keyboard
  shortcut that the file gives a name is listed by its keys, with the name after them. For buttons, keys and places of a ring that open an app or a file,
  or run a script, a box of its own lists each one's whole path and arguments. Read those lists when the file is not
  your own: an action starts at a press of its button. Unless the file gives no button
  or key an action and leaves the gestures (an app's own left and right too) and every
  ring as they are by default, Return presses "Cancel". Importing itself starts nothing.
- An import replaces the kinds of settings the file holds and leaves the others as they
  are; a file made by "Export…" holds them all. (A file from a version before the
  Shortcut Ring leaves your ring as it is.) The new settings are in effect at once.
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
