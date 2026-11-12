# Changelog

What changed in each released version of Scrollio, newest first.

The part under a version's heading is what the update window shows to people who have an
older version, and what the GitHub release says: `scripts/release.sh` reads it. So write
it for the people who use the app, and give the version its part before you tag it.

## Unreleased

- **Trackpad-style scrolling (Beta)** knows more apps. Web apps made with Safari's "Add to
  Dock" and the DuckDuckGo browser are left as they are, like Safari. A web app installed
  from Chrome, Brave or Edge scrolls and bounces like its browser.
- With it on, the first scroll in a Chrome-like app after Scrollio starts already bounces
  like the later ones.
- With it on, an app is no longer left waiting for the end of a scroll: when a finger on
  the trackpad takes over from the wheel, and when the setting is switched while a scroll
  runs.
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
