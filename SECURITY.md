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

- With Accessibility access, the scroll, mouse button and key events of your session pass
  through Scrollio while it runs and is not paused. It changes scroll events, takes the
  buttons and keys you gave an action, and posts the events those actions make. Every
  other key is compared with your bindings and passed on. Scrollio keeps no record of
  what you type.
- It makes no network connection: there is no networking code in it, no updater, no
  analytics and no crash reporter.
- It talks to Logitech mice over HID++ (a Logitech receiver or Bluetooth). What it reads
  and what it writes is in the README, under "Logitech MX mice".
- The released app is signed with a Developer ID, notarized by Apple, runs with the
  hardened runtime without exceptions and has no entitlements. It is not sandboxed: a
  sandboxed app cannot change other apps' events, talk to the mouse or run your scripts.
- "Follow the hand" uses private macOS interfaces, looked up while the app runs. Where
  they are missing the mode is not available.

## What to know before you rely on it

- **A script bound to a button runs with Scrollio's permissions.** A button or key can
  open an app or a file, or run a script. macOS counts a script started by Scrollio as
  part of Scrollio, so it runs with Scrollio's Accessibility access, without a prompt of
  its own. Bind only scripts you trust, and keep them where other programs cannot change
  them.
- **Scrollio's settings are an ordinary preferences file**
  (`~/Library/Preferences/com.nikklemenc.Scrollio.plist`). Any program that runs as you
  can change it, and with it which script a button runs. Such a program could then have
  its own code run with Accessibility access at the next press of that button. Scrollio
  does not check a script before it runs it.
- A script started by Scrollio cannot send Apple events to other apps: Scrollio has no
  permission for them.
- The debug build (`Scrollio Debug.app`) is a developer's tool. Its Scroll Monitor shows
  every scroll, button, pointer and modifier-key event while it is open. Do not hand a
  debug build to anyone as "Scrollio".

## Checking a download

A release is signed by team `8C592KLVN6` and notarized. The README, under "Download and
first launch", has the commands that show it.
