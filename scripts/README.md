# Scripts

Repeatable automation.

- `install.sh`: builds the release app, checks its signature against the installed app's
  (so the Accessibility permission is kept), its entitlements and its binary, stamps it
  with the commit, and installs it to `/Applications`. `--check` stops before installing.
  A `Local.xcconfig` in the repository root (ignored by git, template
  `Local.xcconfig.example`) is passed to the build: another Mac's signing team.
- `release.sh`: builds the app for other people's Macs, from a commit tagged `v<version>`:
  a universal Release build, stripped, signed with the Developer ID certificate, notarized
  by Apple and packed into `build/release/Scrollio-<version>.dmg`, with the debug symbols
  next to it in `Scrollio-<version>.dSYM.zip` (keep it, do not publish it). The image
  gets its name only after the last check. It installs nothing. `--check` stops before
  the notarization, so nothing is uploaded, and needs no tag. It also makes the release
  an update: the build gets its update feed, Sparkle's helper programs are signed with
  the Developer ID, and the finished image is signed with the update key and described
  in `build/release/appcast.xml`, which is published with the image. The root README,
  "Making a release", has the steps.
- `release-lib.sh`: the functions of `release.sh` that can be tried without the
  Developer ID (signing Sparkle's helpers, looking at every program's signature, writing
  the appcast, filling and packing the disk image). `release.sh` sources it; it is not
  run by itself.
- `dmg/`: the window of the disk image, and `dmg/preview.sh`, which builds a sample
  image to look at without a release. See "The disk image's window" below.
- `update-key.sh`: the update key, whose private half is in the login keychain and
  whose public half is `SUPublicEDKey` in `Scrollio/Info.plist`. Without an argument it
  shows the keychain's public key and whether it is the app's; `create` makes the key
  (once, ever), `export <file>` and `import <file>` move the private half.
- `qa/lint-logi-boundary.sh`: enforces the boundary around `Scrollio/Logi/` and
  `Scrollio/Integration/`. Run it by hand after changes there;
  `LogiBoundaryEnforcementTests` runs it as part of the test suite, and `release.sh`
  before it builds.

Every script that calls `xcodebuild` names the project (`-project Scrollio.xcodeproj`),
so a second `.xcodeproj` in the folder does not stop it.

Hand-run diagnostics that are not stable entry points live in `tools/`.

## The disk image's window

Opened, the image is a window of 660 x 420 pt: Scrollio's icon, an arrow and the
Applications folder on a picture. `LICENSE.txt` and `Acknowledgements.txt` are on the
image too, below the part of the window that shows when it opens. Finder takes all of
this from two files on the image, and `dmg/` holds both ready:

- `dmg/background.tiff`, the picture, drawn by `dmg/draw-background.swift`. It is one TIFF
  with the picture twice, 660 x 420 px and 1320 x 840 px (joined by
  `tiffutil -cathidpicheck`): Finder takes the one that fits the display, so it is sharp
  on a Retina display. The arrow and the line of text are part of the picture.
- `dmg/DS_Store`, the layout, on the image under Finder's name for it, `.DS_Store`: the
  window's size, the size of the icons and of their names, which picture, and where each
  icon sits. `dmg/write-layout.swift` writes it. Finder itself writes such a file only
  when it is scripted or used by hand, and its file names the Mac it was made on (the
  path of the image file, the disk and the user); this one holds nothing but the layout.

`stage_disk_image` in `release-lib.sh` is the one place that fills the image's folder
(the app, the link, the two text files, the picture, the layout), and `make_disk_image`
packs it; `release.sh` and `dmg/preview.sh` both use them. `release.sh` stops before it
builds when the picture or the layout is missing. No run scripts Finder or asks for a
permission.

To look at the window: `scripts/dmg/preview.sh`, then
`open build/dmg-preview/Scrollio-preview.dmg`. It takes a built or the installed
Scrollio.app (or the one given as its argument; without any, a stand-in with the generic
icon), signs nothing and is for this Mac only. Eject an image named Scrollio that is
open before you open another.

To change it:

- The picture: edit `dmg/draw-background.swift`, run
  `swift scripts/dmg/draw-background.swift`, look at the preview, commit the TIFF with
  the script.
- A size, a place or an item: edit the numbers at the top of `dmg/write-layout.swift`
  (and the picture, when the arrow has to move), run
  `swift scripts/dmg/write-layout.swift`, look at the preview, commit `dmg/DS_Store`
  with the script. An item is also added to `stage_disk_image`. `ReleaseReadinessTests`
  holds the numbers and compares the names of the layout with what is staged: change
  them there too.

What to know:

- Finder finds the picture by the volume's name (Scrollio) and its path on the image
  (`.background/background.tiff`): the layout holds both, so they change together. With
  two images named Scrollio open, both windows take the picture from the one opened
  first.
- The layout stores the window with its title bar, counted as 28 pt (macOS 14 and 15).
  Where the bar is higher (32 pt on macOS 27), the lowest 4 pt of the picture are not
  seen; counted as 32 pt, the older systems would show a strip without picture.
- The two text files make the window's content taller than the window: where macOS
  always shows scroll bars (its default with a mouse connected), expect one in the
  window.
- The tests read the files; whether Finder shows the window as meant, only a look at the
  preview tells, in the light and in the dark appearance.
