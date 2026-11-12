# Smooth scrolling


- Five feels (Direct, Quick, Smooth, Glide and Float) set how long the page glides on;
  Speed sets how far one click moves it. A moving preview in the Scrolling pane shows the
  feel.
- Reverse wheel direction (the wheel only, not the trackpad).
- Under Advanced: an exact glide time, the smallest step, and
  "Trackpad-style scrolling (Experimental)": apps treat the wheel like a trackpad and bounce at
  the ends of a page. Sideways scrolling stays as it is. What it does in which app, and
  its limits:
  [Trackpad-style scrolling (Experimental)](#trackpad-style-scrolling-experimental).
- While you hold a key: "Scroll faster" (5 × the distance), "Scroll sideways" and "Pause
  smoothing" (exact steps, for example to zoom with ⌘). A mouse button can hold them
  too. These keys work while Smooth scrolling is on.
- "Reset to Defaults" can be taken back: for a few seconds the button reads "Undo Reset".
- Per app (the Apps pane): an app uses the Scrolling settings or keeps its own. "Change
  scrolling only in these apps" leaves every other app to macOS; buttons and gestures
  still work everywhere. "Smooth Scrolling in …" in the menu bar menu turns smoothing on
  or off for the app in front.
- Trackpads and the Magic Mouse are left alone. With several displays, the motion is
  timed to the display under the pointer.

## Trackpad-style scrolling (Experimental)

Off by default. With it on, a wheel scroll up or down reaches an app in the form a
trackpad's scroll has: a touch, and for some apps a glide after it. Apps then treat the
wheel like a trackpad and bounce at the ends of a page. Scrollio sends the same motion as
with it off (to a Chromium-based app, at the Direct feel, a click now and then comes out a
pixel apart); only the form differs, and apps do not all read it the same way.

While it is on, two more switches stand under it in Scrolling › Advanced and say where it
works:

- **In browsers** (on at first): web pages in Safari, in Chrome-like browsers and in
  Firefox, and apps built like them (VS Code, Slack). The first way below. With it off
  these apps scroll as with the main switch off, and Scrollio asks them nothing.
- **In Mac apps** (off at first): lists and documents in every other app, the second
  way below. An app bounces at a page's end where Scrollio can read the scroll bar under
  the pointer, or, where there is none to read, can see the content under the pointer
  move with the wheel; elsewhere it scrolls as usual (see [Permissions](privacy.md#permissions)).
  It is good in Finder; in some apps scrolling gets
  worse with it (seen in Messages, whose list of conversations says "at the end" when it
  is not, and in Calendar), which is why you choose it. With it off these apps scroll as
  with the main switch off, and Scrollio asks them nothing through Accessibility.

Both are settings of the whole of Scrollio. An app with its own settings in the Apps pane
still has its own main switch, and the two apply where that is on.

The form is sent in one of three ways:

- Chrome, Brave, Arc, Dia and the other browsers and apps built on Chromium (Electron
  apps such as VS Code and Slack, Spotify, a web app installed from such a browser), and
  Firefox and the other apps built on its engine (Thunderbird, Zotero): a short touch and
  then its glide. These apps move the page by every step they are sent, in the touch and
  in the glide, and bounce at a page's end by the glide's speed.
  Dia and Arc are Chromium inside a program of their own, and what that program draws
  itself (the sidebar of tabs) is not a web page: under this form it stopped in
  mid-scroll (seen in Dia). In such an app Scrollio looks at what is under the pointer
  (see [Permissions](privacy.md#permissions)) and tells the view that holds a web page from
  everything else, without asking it what it is: that view has no parts of its own, is
  large, and is the same view some points further on. The page keeps this form.
  Everything else there scrolls as with the main switch off, the right distance without
  a bounce (Dia's sidebar shows no scroll bar to read: seen in its log); where it does
  show one, and "In Mac apps" is on, it scrolls in the form for every other app. (Built
  from Chromium's code and from what macOS answers; seen in Dia on macOS 27.2: the
  sidebar scrolls its whole way and the page keeps its bounce. Arc was not seen.)
- Every other app: one touch that lasts until the scroll has run out, with no glide
  after it. These apps follow a touch to its end, and after a touch that ends at speed
  they add a glide of their own. So that they add nothing, the touch ends a fifth of a
  second after the page last moved; a turn of the wheel in that time goes on with the
  same touch. When something cuts a scroll short (a click, a finger on the trackpad, the
  wheel going on over another pane or another app, Pause), the touch ends at once, and
  Scrollio sends what a trackpad sends when two fingers tap it: by the notes of two other
  mouse tools (Mac Mouse Fix, LinearMouse), that is what stops an app that would glide on.
  For this form Scrollio has to know where the page ends, because such an app holds a
  page stretched past its end for as long as a touch lasts. While such a scroll runs, and
  for each wheel event it takes in at a page's end, it reads, through Accessibility, what
  kind of element is under the pointer and the position of that view's scroll bar, and
  nothing else; nothing of it is sent anywhere, and only the kinds and the position go
  into the scroll log (see [Privacy](privacy.md#privacy)).
  When the page reaches its end, the touch ends at once and the app bounces by itself;
  while the wheel still turns into that end, nothing more is sent, as long as each new
  look finds the same scroll bar under the pointer, still at that end, and for four
  seconds at most; a scroll that starts at the end makes one small bounce. A view whose
  scroll bar cannot be read (no scroll bar, a bar that does not count from 0 to 1) is
  given a second way: Scrollio asks the element under the pointer where it is on the
  screen, once per display frame. Such a scroll starts as with the switch off; when the
  element has moved with what was sent (three readings, 48 points, within a quarter),
  the touch opens, and when the element then moves less than half of what is sent (over
  a tenth of a second and 30 points), the page is at its end: the touch ends at once and
  the app bounces. After that nothing is held back: the wheel that still turns scrolls
  as with the switch off. A view where the element does not move with the wheel or
  gives no position, and an app that does not answer in time, scroll as with the switch
  off. (This second way was built for the conversation in Messages from its log. Seen
  there on macOS 27.2: it works only in part, which is one reason the whole feature is
  marked Experimental.)
- Safari, the web apps made with its "Add to Dock" and the DuckDuckGo browser: on macOS
  27 and later the same short touch and glide as Chrome gets. For Safari this was seen on
  one screen (macOS 27.2, 2026-11-12: smooth, with the bounce; WebKit's own log said it
  followed every glide it was sent); DuckDuckGo is the same engine and was not seen. On
  macOS 14, 15 and 26 nothing changes for them: there the wheel's hardware event cannot be
  taken off what is sent, and with it on a glide these browsers do not scroll smoothly.
- Maps, Find My, Calendar, iPhone Mirroring, Blender and the Godot editor: nothing
  changes. By what people who use other mouse tools report, they do something else with a
  trackpad's scroll than with a wheel's (the wheel pans a map where it zoomed, or orbits
  a 3D view), or do not scroll as they should. For these the switch does nothing, and
  neither does their own "Trackpad-style scrolling (Experimental)" switch when you give one of
  them its own settings in the Apps pane.

Scrolling sideways (with Shift, "Scroll sideways" or the thumb wheel) stays as it is with
the switch off, in every app. In a trackpad's form a sideways scroll is a swipe, and apps
go back or forward a page on it, or switch tabs.

What an app is sent also reads like a trackpad's events in the details: each has a time
of its own, evenly spaced (apps take the speed for a bounce from it), its own line count,
and, on macOS 27 and later, nothing of the wheel's hardware event left on it (with that
on a glide, a web view replaces the glide by one of its own). On macOS 14, 15 and 26 the
hardware event stays on, as before: taking it off was only run on macOS 27.

How sure this is. It was worked out from how AppKit, WebKit, Chromium and Firefox handle
a trackpad's scroll (read in their code, AppKit's on macOS 27.2), from what other mouse
tools send, and from measurements in a web view that ran without a display. What one
person then saw on a screen, on macOS 27.2 in November 2026:

- Right: web pages in a Chrome-like browser (Dia) and in Safari; Finder with "In Mac
  apps" on (the page bounces at its end, also when the wheel turns up and down, and
  nothing flies on in mid-page); the sidebar of tabs in Dia.
- In part: the conversation in Messages (the second way, by the content under the
  pointer).
- Not seen at all: Firefox, the DuckDuckGo browser, Arc, and macOS 14, 15 and 26.

No test may read another app's interface, so in the tests the reading of another app runs
against a stand-in; what it met in a real app is in the scroll log. That is why this is
marked Experimental: expect it to be right in browsers and in Finder, and uneven
elsewhere.

Its limits:

- A list that macOS draws inside the windows of an app that runs Chromium as its
  application (Chrome's print dialog, a native panel in an Electron app) gets that app's
  form, and may scroll shorter than the same list in Finder. In Dia and Arc a scroll
  over such a list, at a place Scrollio has not looked at in the last minute, still has
  that form for its first frames, until the look has answered (a few milliseconds; while
  the app is busy, up to a few tenths of a second). And the look can guess wrong: a list
  drawn as one large view without parts, a third of the window wide or more, is taken for
  a page and stops short; a page is taken for something else while Chromium's
  accessibility support is on (VoiceOver, for one), or where three pages stand side by
  side, and then scrolls without its bounce. An Open
  or Save dialog is drawn by a process of macOS's own: it is
  treated as "every other app", and an app's own settings in the Apps pane do not reach
  it. (From how macOS builds these dialogs; not checked on a screen.)
- An app outside the Applications folders is treated as "every other app", also when it
  is built on Chromium or on Firefox's engine: Scrollio looks into no bundle elsewhere
  (see [Privacy](privacy.md#privacy)). In a Chromium-based app this has a price: the look at
  what is under the pointer asks the view that holds a web page what it is, and at that
  question Chromium switches on its accessibility support for web content, which makes
  the app slower until it is quit (read in Chromium's code, where it sits behind one of
  Chromium's own switches; not measured). Move such an app to Applications, or turn
  "Trackpad-style scrolling (Experimental)" off for it in the Apps pane.
- An app that tells a mouse from a trackpad by these events takes the wheel for a
  trackpad. In some 3D and design apps the wheel may then pan where it used to zoom. The
  ones Scrollio knows by name are left alone (above); Autodesk Fusion and Rhino are
  reported to be such apps too, and are not known by name. A game made with Godot has a
  name of its own and is not left alone either: by Godot's code a game that listens for
  the wheel's steps gets none from a trackpad's scroll (it gets a pan instead). Turn it
  off for such a game in the Apps pane.
- A scroll is either up-down or sideways. Turning the other wheel while a scroll still
  glides cuts that glide short with the switch off too (what the first wheel had left is
  dropped); with it on the scroll ends at once, so a little more is lost (a click and a
  sideways click 150 ms later: 124 of the 205 px, against 166 with the switch off).
  Pressing or letting go of "Scroll sideways" while a scroll with a trackpad's form still
  glides ends that scroll. And a sideways list does not bounce at its end.
- A device whose turns go both ways at once (a trackball, a wheel that tilts as it
  turns) keeps the kind of scroll it began with until the other direction leads two to
  one.
- When the wheel keeps turning at the end of an inner pane (a chat, a text box), the page
  around it may not take over until the scroll has ended and a new one begins; with the
  switch off it takes over at once. (From Firefox's code: an app keeps a trackpad's scroll
  on the pane it began on.)
- What ends the touch by itself is the display's next frame, a fifth of a second after
  the page last moved. Should the display send no frame then (suspected for a display
  that goes to sleep in that moment), the touch stays open until Scrollio's keeper ends
  it, 5 to 10 seconds later; that scroll's line in the log ends "ended by the keeper".
- At the end of a page: where the scroll bar can be read, the touch ends when the page
  arrives, a frame or two late (the reading follows the frames), so the page can go a
  little past its end before the app's own bounce takes over. A page that is at its end
  when a scroll starts there for the first time gets its small bounce and then plain
  scrolling, which can cut that bounce short; from the second time on the rest is held
  back, for as long as the same scroll bar is found under the pointer. A wheel that is
  spun into an end for longer than four seconds gets one more small bounce and plain
  scrolling after that. A page whose length changes while it scrolls (a list that loads
  more) can look for a moment as if it moved the wrong way: the rest of that scroll is
  then plain. Where the scroll bar cannot be read the scroll is as with the switch off:
  no stretch and no bounce.
- When the wheel is turned quickly up and down across a page's end, the page bounces only
  if it rests at that end for about 170 ms before the wheel turns back. At quicker turns
  the frames of the way back pull the page off the end before its arrival is read, and
  there is no bounce. (From runs against a stand-in that answers as slowly as Finder did
  while it scrolled, 80 ms: with a turn every 0.25 s one arrival in 40 was read, with a
  turn every 0.4 s all of them.)
- Some views in an app that gets this form still scroll as with the switch off, because
  the first scroll area above the pointer has no vertical scroll bar that can be read:
  the text of a message in Mail (over the message's header the form is there), a sideways
  shelf inside an up-down page (App Store, Music, TV), and apps made with Qt or Flutter.
  (Derived from where the look stops and from how these views are built; seen on no
  screen. The scroll log names the step that failed.) So does a view whose content fits:
  it has no bar, or a disabled one (what macOS answers for such a view was run against
  macOS 27.2 without a screen).
- What the reading costs the app that is read: about ten questions for the look at the
  start of a scroll, and one per display frame while a touch is open. The first look at a
  web view inside such an app (a message in Mail, a help window) switches on that web
  view's own accessibility support, and it stays on for as long as its web process lives
  (read in WebKit's code; what it costs there was not measured). Apps built with SwiftUI
  (System Settings) are suspected to build their accessibility tree at the first question
  in the same way.

If one app scrolls oddly with it, give that app its own settings in the Apps pane and
turn it off there.
