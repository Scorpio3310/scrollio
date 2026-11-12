# Security

Scrollio holds the Accessibility permission: it receives the mouse's and the keyboard's
events and can post events of its own. A weakness in such an app matters more than in most.

## Reporting a problem

Please report it privately, not in a public issue. On Scrollio's GitHub page open the
**Security** tab and choose **Report a vulnerability**
(<https://github.com/Scorpio3310/scrollio/security/advisories/new>). If that button is not
there, open an issue that says only that you have a security report, without any detail,
and you will be asked how to pass it on.

Say what you found, in which version (General shows the version, the build and the
commit), on which macOS, and how to make it happen.

Scrollio is one person's project. There is no bounty and no promised answer time; a
report is read, answered, and credited if you wish. Fixes go into the newest release only.

## What Scrollio can see and do

- With Accessibility access, scroll and mouse button events pass through Scrollio while
  it runs and is not paused. It changes scroll events, takes the buttons and keys you
  gave an action, and posts the events those actions make.
- Key presses pass through Scrollio only while a key is bound to an action in Buttons,
  while a button you hold stands for a modifier, or while you record a key in Settings.
  Otherwise it only listens to them, for the keys under Scrolling › While you hold a key,
  and cannot delay them. It keeps no record of what you type.
- It makes no network connection: there is no networking code in it, no updater, no
  analytics and no crash reporter.
- It talks to Logitech mice over HID++ (a Logitech receiver or Bluetooth). What it reads
  and what it writes is in the README, under "Logitech MX mice".
- The released app is signed with a Developer ID, notarized by Apple, runs with the
  hardened runtime without exceptions and has no entitlements. It is not sandboxed: a
  sandboxed app cannot change other apps' events, talk to the mouse or run your scripts.
- "Follow the hand" uses private macOS interfaces, looked up while the app runs. Where
  they are missing the mode is not available. Starting a script (see below) uses one
  more function that is in no public header.

## What to know before you rely on it

- **A script a button runs is a program of its own.** A button or key can open an app or
  a file, or run a script. Scrollio starts the script so that macOS judges it by itself:
  it has none of Scrollio's permissions, not its Accessibility access either, and macOS
  asks for the script's own when it needs one. On a macOS without the function for this,
  the script runs as Scrollio's child, with Scrollio's permissions, and the `app` log
  says so.
- **Scrollio's settings are an ordinary preferences file**
  (`~/Library/Preferences/com.nikklemenc.Scrollio.plist`). Any program that runs as you
  can change it, and with it what a button opens or runs. What it plants there is then
  started at a press of that button: as you, like the program that planted it, and
  without Scrollio's Accessibility access (with the exception named above). Scrollio
  does not check a script before it runs it. A planted binding cannot hang on ordinary
  typing or clicking: a key runs an action only with ⌘, ⌥, ⌃ or ⇧ held or when it is an
  F-key, and the left and right mouse buttons never do.
- The debug build (`Scrollio Debug.app`) is a developer's tool. Its Scroll Monitor shows
  every scroll, button, pointer and modifier-key event while it is open. Do not hand a
  debug build to anyone as "Scrollio".

## Checking a download

A release is signed by team `8C592KLVN6` and notarized. The README, under "Download and
first launch", has the commands that show it.
