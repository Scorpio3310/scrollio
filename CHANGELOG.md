# Changelog

What changed in each released version of Scrollio, newest first.

The part under a version's heading is what the update window shows to people who have an
older version, and what the GitHub release says: `scripts/release.sh` reads it. So write
it for the people who use the app, and give the version its part before you tag it.

## Unreleased

- **Trackpad-style scrolling (Beta)** in apps that are not browsers (Finder, Notes, a
  message in Mail): the whole scroll is now sent as one touch. Before, the end of a scroll
  was sent as a glide. By how these apps read such events they follow a touch to its end
  and not a glide they are sent, so a click should have stopped short, more so with a long
  glide time, and should now go as far as with the switch off. That is derived, not yet
  seen on a screen. At the end of a page the page can stay stretched a little longer.
- **Trackpad-style scrolling (Beta)** knows more apps. Web apps made with Safari's "Add to
  Dock" and the DuckDuckGo browser are left as they are, like Safari. A web app installed
  from Chrome, Brave or Edge scrolls and bounces like its browser.
- With it on, a Chrome-like app that comes to the front is known before you scroll in it,
  so its first scroll already bounces like the later ones. (An app that was in front when
  you turned the switch on, or that you scroll in without bringing it to the front, is
  known from the scroll after its first, as before.)
- With it on, a scroll that runs is closed when the setting is switched, and the wheel's
  scroll is closed before a finger on the trackpad begins its own (nothing kept the two in
  that order before; that an app ever got them the wrong way round was not seen).
- The README says what Trackpad-style scrolling does in which app, and where its limits
  are.

## 1.0.1

- **Scrollio updates itself.** If you allow it, Scrollio asks GitHub once a day whether
  there is a newer version, shows what is new and installs it. General has the two
  switches and "Check Now"; "Check for Updates…" is in the menu bar menu and in the
  Scrollio menu.
- An update is installed only when it carries the author's signature; a download that
  does not is never opened.
- This is the first version that can update itself: from 1.0.0, download this one by hand.

## 1.0.0

First public release: smooth, trackpad-like scrolling for any mouse, actions for mouse
buttons and keys, mouse gestures, thumb wheel actions, and settings for Logitech MX mice.
