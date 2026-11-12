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
- A released copy updates itself with [Sparkle](https://sparkle-project.org), and that
  is its only use of the network: it asks GitHub for the file `appcast.xml` of the
  newest release (once a day if the user allowed it, and on "Check for Updates…") and
  downloads the disk image of an update from GitHub. There is no analytics and no crash
  reporter, and Sparkle's system profile is off. A copy built from source has no update
  feed and makes no network request.
- It talks to Logitech mice over HID++ (a Logitech receiver or Bluetooth). What it reads
  and what it writes is in the README, under "Logitech MX mice".
- The released app is signed with a Developer ID, notarized by Apple, runs with the
  hardened runtime without exceptions and has no entitlements. It is not sandboxed: a
  sandboxed app cannot change other apps' events, talk to the mouse or run your scripts.
- "Follow the hand" uses private macOS interfaces, looked up while the app runs. Where
  they are missing the mode is not available. Starting a script (see below) uses one
  more function that is in no public header.

## How an update is trusted

- The feed (`appcast.xml`) only says which version is the newest and where its disk
  image is. The image must carry an EdDSA signature made with Scrollio's update key,
  whose public half is in the app (`SUPublicEDKey`), and it is checked before the image
  is opened (`SUVerifyUpdateBeforeExtraction`). Whoever controls the feed or the
  download, GitHub's account included, cannot make an installed copy install something
  else, and cannot make it go back to an older version.
- In place of that signature Sparkle also accepts a disk image signed with the same
  Developer ID as the installed app: that is how a lost update key is replaced. So the
  two things to guard are the update key and the Developer ID certificate, both on the
  author's Mac; neither is in this repository.
- The address of the feed is the one in the app's Info.plist. A `SUFeedURL` written into
  the preferences file is not used.
- The feed itself is not signed. What whoever controls it can do: keep an update away;
  show other release notes in the update window (Scrollio's own are Markdown, but a
  feed can also send HTML or point to a page: scripts in it do not run, pictures and
  styles from the web do load); put a link in that window that opens a web page in the
  browser; call an update critical; and offer an older release that was properly
  signed, to copies older than it.
- With a check Sparkle can send a profile of the Mac. It is off, and Scrollio hands
  Sparkle an empty list of what such a profile may hold, so a switch planted in the
  preferences file sends nothing either.
- The app in an update is signed with the Developer ID and notarized like a download,
  and Sparkle's helper programs inside the app carry the same signature.

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
- **A settings file can give a button a script.** General › Settings file › Import…
  takes a JSON file that can hold everything the panes can set: buttons and keys that
  open an app or a file or run a script, that press any key combination, that run a
  system action such as Move to Trash, or that run a Logitech action. What Scrollio
  does about it:
  - It reads only a regular file of at most 2 MB with at most 1000 buttons and keys and
    1000 apps. It takes only the settings on its list (anything else in the file is
    ignored), only entries this version can read and only actions this version runs;
    the others are left out, not kept for a later version. Numbers of Scrolling are
    brought into the range the panes and the scroll engine work with. What is imported
    is what was understood, written by Scrollio's own code.
  - Before anything changes, a sheet shows what the file holds: every button and key
    with what it will do, in the words of the Buttons pane, and every gesture direction
    whose action is not the default one. For an action that opens or runs something it
    also lists the whole path and the arguments, and for an app the identifier by which
    macOS would find it when nothing is at the path. Characters that draw nothing, are
    blank or turn the text around are written out, and a run of them is one short
    mark, so that no part of a path or an argument is out of sight. Letters that look
    like other letters are not told apart: read a path, do not glance at it. Unless the
    file gives no button or key an action and leaves the gestures at their defaults,
    Return presses "Cancel".
  - Importing starts nothing. An imported action runs like any other, at a press of its
    button or key, under the rule above (a key only with ⌘, ⌥, ⌃ or ⇧ or as an F-key,
    never the left or right button), and a script is started as described above.
  - A file cannot switch on "Let Scrollio manage this mouse" or "Open at login", and
    cannot touch the updater's settings: none of them is read from a file. So the
    Logitech settings of a file (wheel mode, pointer speed, haptics) reach a mouse only
    where the user had already allowed Scrollio to write its settings.
  - Two things reach a Logitech mouse whatever that switch says, for an imported
    setting as for one made by hand, and an import can bring both: a Logitech button
    that gets an action (and a gesture button the mouse is to track) is asked of the
    mouse, and a Logitech action (switch the mouse to another computer, change the
    wheel mode or the pointer speed) writes to the mouse when its button, key or
    gesture is used. The sheet lists these actions with all the others.
  - An import only starts from that button in Settings. Scrollio registers no file type
    and opens no file by itself, so nothing outside Scrollio can start one.

  So: do not import a file from someone you do not trust without reading those lists.
  The settings from before an import are kept, and "Restore…" brings them back.
- The settings from before an import are files in
  `~/Library/Application Support/com.nikklemenc.Scrollio/Settings Backups`. Like the
  preferences file, any program that runs as you can change them; a backup chosen with
  "Restore…" goes through the same sheet, with the same lists, before it is put in
  effect.
- The debug build (`Scrollio Debug.app`) is a developer's tool. Its Scroll Monitor shows
  every scroll, button, pointer and modifier-key event while it is open. Do not hand a
  debug build to anyone as "Scrollio".

## Checking a download

A release is signed by team `8C592KLVN6` and notarized. The README, under "Download and
first launch", has the commands that show it. An update that Scrollio installs itself is
checked as described above; nothing has to be compared by hand.
