# Changelog

What changed in each released version of Scrollio, newest first.

The part under a version's heading is what the update window shows to people who have an
older version, and what the GitHub release says: `scripts/release.sh` reads it. So write
it for the people who use the app, and give the version its part before you tag it.
`## Unreleased` collects what the next version brings; it becomes that version's part
(the heading gets the version) before the tag.

## Unreleased

- **Trackpad-style scrolling (Beta)** now says where it works. While it is on, two
  switches stand under it in Scrolling › Advanced. "In browsers" (on): web pages in
  Safari, Chrome-like browsers and Firefox, and apps built like them. "In Mac apps"
  (off): lists and documents in every other app, for which Scrollio reads the scroll bar
  under the pointer; good in Finder, worse than without it in some apps (Messages,
  Calendar). **If you had the Beta on in 1.0.1: Mac apps now need their own switch**, and
  scroll as without the Beta until you turn it on. Both are in the settings file.
- **Trackpad-style scrolling (Beta)** in apps that are not browsers (Finder, Notes, a
  message in Mail): the whole scroll is now sent as one touch, which ends a fifth of a
  second after the page last moved. Before, the end of a scroll was sent as a glide. By
  how these apps read such events they follow a touch to its end and not a glide they are
  sent, and after a touch that ends at speed they add a glide of their own. So a click
  should have stopped short, more so with a long glide time, and should now go exactly as
  far as with the switch off. When a click, a finger on the trackpad or another app cuts a
  scroll short, Scrollio now also sends what a trackpad sends when two fingers tap it, so
  that the app stops there. All of this is derived from how macOS reads these events, not
  yet seen on a screen. At the end of a page the page can stay stretched a little longer.
- **Trackpad-style scrolling (Beta)** at the end of a page in apps that are not browsers.
  Such an app holds a page stretched past its end for as long as the wheel's scroll lasts;
  with a free-spinning wheel that was a second or two before the page came back (seen in
  Finder). Scrollio now reads where the page is (through Accessibility: the kind of the
  element under the pointer and the position of its scroll bar, nothing else; only those
  kinds and the position go into the scroll log) and ends the scroll's touch the moment
  the page arrives, so that the app bounces by itself as it does for a trackpad; while the
  wheel keeps turning into the end nothing more is sent, as long as the same scroll bar is
  found under the pointer at that end, and for four seconds at most. Where a view's
  scroll bar cannot be read, that view scrolls as with the switch off (the README lists
  the views known to be such). Seen on one Mac, in Finder; in the tests this part runs
  against a stand-in, because a test may not read another app.
- **Trackpad-style scrolling (Beta)** in Dia and Arc: the sidebar of tabs (drawn by the
  browser itself, not a web page) stopped in mid-scroll. Scrollio now looks at what is
  under the pointer in these two and tells a web page from everything else without
  asking the page's view what it is. A page scrolls as before; everything else scrolls
  as without the Beta, the right distance without a bounce. Built from Chromium's code,
  from what macOS answers and from one log of Dia; the new rule is not seen on a screen
  yet.
- **Trackpad-style scrolling (Beta)** is more careful with what it asks an app. It never
  asks the app itself what it is (Chrome and Electron apps switch on their accessibility
  support at that question, and get slower), it does not look at an app before it knows
  whether the app is built on Chromium, and a view whose content fits is no longer taken
  for a page at its top.
- **Trackpad-style scrolling (Beta)** now works in Safari on macOS 27: Safari scrolls and
  bounces like Chrome does with it (seen on one Mac: smooth). Before, Safari was left as it
  was, because with the wheel's hardware event on what it is sent it did not scroll
  smoothly; that is now taken off. The DuckDuckGo browser gets the same (same engine; not
  seen). On macOS 14, 15 and 26 both stay as they are.
- **Trackpad-style scrolling (Beta)** knows more apps. Firefox and the apps built on its
  engine (Thunderbird, Zotero) now get the same form as Chrome-like apps, a short touch and
  its glide: by Firefox's code that is what makes it bounce like a trackpad (not yet seen
  on a screen). Web apps made with Safari's "Add to Dock" are treated as Safari. Maps,
  Find My, Calendar, iPhone Mirroring, Blender and the Godot editor are left as they are:
  people who use other mouse tools report that with a wheel in a trackpad's form these
  pan or turn the view instead of zooming, or do not scroll as they should. A web app installed from Chrome, Brave or Edge scrolls and bounces like its
  browser.
- With it on, scrolling sideways (Shift, "Scroll sideways", the thumb wheel) now stays as
  it is with the switch off. In a trackpad's form a sideways scroll is a swipe, and by
  their code Chrome and Firefox go back or forward a page on it.
- With it on, what an app is sent reads more like a trackpad's events: each has a time of
  its own, evenly spaced (apps take the speed for a bounce from it), its own line count,
  and nothing of the wheel's hardware event left on it (a web view that found it on a
  glide replaced the glide by one of its own: measured in a web view without a display).
  In Chrome-like apps and Firefox the touch now begins with the first step the page
  moves, and its end goes out together with the glide's beginning. The motion itself is
  what it was. On macOS 14, 15 and 26 the wheel's hardware event stays on, as before:
  taking it off was only run on macOS 27.
- With it on, a Chrome-like app that comes to the front is known before you scroll in it,
  so its first scroll already bounces like the later ones. (An app that was in front when
  you turned the switch on, or that you scroll in without bringing it to the front, is
  known from the scroll after its first, as before.)
- With it on, a scroll that runs is closed when the setting is switched, and the wheel's
  scroll is closed before a finger on the trackpad begins its own (nothing kept the two in
  that order before; that an app ever got them the wrong way round was not seen).
- The README says what Trackpad-style scrolling (Beta) does in which app, and where its
  limits are.
- On macOS 26 the line between the sidebar and the settings in the Settings window is gone.
- "You're up to date!" and a failed check are now the alert every Mac app shows, with
  Scrollio's icon and an OK button, instead of a notice at the top of the screen.
  Scrolling, buttons and gestures go on working while it is open.
- The window of an update you asked for opens where you are, also over a full-screen
  app; there it used to open out of sight.
- An update that the daily check finds no longer opens a window by itself. Scrollio
  shows in the Dock with a badge, and the window opens when you come to Scrollio or
  choose "Update to Scrollio …" in its menu.
- The disk image opens as a window that shows what to do: Scrollio's icon, an arrow and
  the Applications folder.
- Under the Beta switch the two places stand a little further in, and the three switches
  cannot contradict each other: the last place switched off switches the Beta off, and the
  Beta switched on with both off comes on in browsers.
- The purple of the app's switches, selection and buttons is a little darker.

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
