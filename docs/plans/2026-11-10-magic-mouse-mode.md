# Magic Mouse-style behaviour for MX Master 3 / 3S / 4

Date: 2026-11-10. Personal build, branch `feat/gesture-navigation`. Status: phase 0 done, phase 1 in progress.

## Goal

Make Logitech MX Master mice behave like an Apple Magic Mouse where it matters:

1. Switching Spaces follows the hand. Hold the gesture button, move sideways, and the desktop
   moves with the mouse; it can rest between two Spaces and go back. macOS completes or cancels
   on release.
2. Scrolling has Magic Mouse momentum: exact single notches, a glide after a flick, a stop on a
   reverse tick, and trackpad phases so apps rubber-band.
3. One-click profiles (Magic Mouse, MX Default, Direct) that set scrolling, gesture mode and the
   thumb wheel together.

## What the research found (phase 0)

Five read-only research passes; nothing below has been verified on real hardware yet.

- **Magic Mouse**: the Spaces swipe is the same "fluid dock" action a trackpad sends (driver
  thresholds: start 3.3 mm, complete 30 mm, inertia 0.5 s). Page back/forward is scroll events plus
  AppKit swipe tracking. Mission Control and smart zoom are discrete taps. Scrolling is
  pixel-precise with driver-made momentum.
- **Synthetic dock swipe**: a `CGEvent` of type 30 posted to the session tap, phases
  began 1 / changed 2 / ended 4 / cancelled 8, cumulative progress, velocity on end.
  - macOS <= 26 reads private CGEvent fields (110, 123, 124, 132, 135, 129/130, ...).
  - **macOS 27 ignores those fields** and reads an attached IOHIDEvent
    (`SLEventSetIOHIDEvent`; HID type 23, motion / flavor 3 / progress, velocity child type 9,
    16.16 fixed point). The Dock applies the natural-scrolling preference itself.
  - Motion 1 = Spaces, 2 = Mission Control / App Expose, 3 = Show Desktop / Launchpad.
  - Known problems: stuck transitions (Mac Mouse Fix re-sends the end event), stutter with
    high-polling mice (send one frame per display refresh), swiping past the last Space can wedge
    the Dock, direction with natural scrolling off needs a live check.
  - Probe (never run): `research-magic/dockswipe/DockSwipeProbe.swift` in the session scratchpad.
- **Scroll physics** (WebKit's model of the system curve): x0.975 per 8 ms, below 250 units/s
  x0.91 per 8 ms, end under 0.5 px per frame. Mos's simulate-trackpad path truncates fractional
  pixels when posting.
- **Logitech hardware**: all three mice support raw XY diversion on the gesture button `0x00C3`
  (MX Master 4 also on the haptic panel `0x01A0`): the firmware stops moving the pointer and
  reports deltas over HID++ (0x1B04 event fn1, signed 16-bit dx/dy; arm 0x33, disarm 0x22).
  MX Master 4 haptics: 0x19B0 fn4 play waveform (0x04 at threshold, 0x01 on commit). Thumb wheel
  0x2150 can be diverted for 6x resolution and touch state.
- **Mos integration**: gesture settings are global; the motion tap already feeds
  `InputProcessor.handleMouseGestureMovement`; `clearActiveBindings` is the single cancel path.

## Phases

Each phase ends with: full test suite, Logi boundary lint, Release build, install, hardware check
by the owner.

### Phase 1: desktop follows the hand (the example)

- `MouseGestureSettings.mode`: `discrete` (default, today's behaviour) or `interactive`.
- `DockSwipeSynthesizer`: injectable driver; HID layout on macOS 27+, field layout below;
  availability probe with automatic fallback to discrete; inert under XCTest.
- `InteractiveGestureSession`: pure state machine. Arms on button down, locks the axis at 8 px
  (1.2 dominance), horizontal drives the Spaces swipe (one screen width = one Space), vertical
  keeps today's discrete up/down actions. Release: never moved -> click action; moving back ->
  cancel; otherwise end with velocity. Exactly one terminal event; 10 s watchdog.
- Posting happens once per display frame on the main thread, never inside the tap callback.
- Gesture Settings popover: "One action per hold | Follow the hand (experimental)".
- First hardware check: direction with natural scrolling on/off, no stuck transition, behaviour at
  the first and last Space.

### Phase 2: Magic Mouse scrolling

- `ScrollMomentum` coast (WebKit curve) seeded from input speed; flick threshold 8-16 lines/s so
  single notches stay exact; reverse tick cancels; no coast with modifiers held.
- No synthetic momentum or phases in free-spin (the wheel has its own inertia); no phases on the
  horizontal axis.
- Fix fractional-pixel truncation when posting (carry sub-pixels).
- New scroll preset "Magic Mouse": step 33.6, speed 1.8, duration 2.5, simulate trackpad on,
  free-spin 1.0 / 1.2x, acceleration 0. Values are estimates to tune on hardware.

### Phase 3: Logitech specifics

- Raw XY diversion for the held gesture button (firmware-frozen pointer, acceleration-free deltas);
  keep the CGEvent path as fallback. Drop the first sample of each hold.
- MX Master 4 haptic pulse at the swipe threshold and on commit.
- Thumb wheel as swipe between pages (phased horizontal scroll first, HID++ divert later).

### Phase 4: profiles and polish

- Profiles row in the Mouse tab (Magic Mouse / MX Default / Direct / Custom) plus a status-menu
  submenu; applying never touches per-app settings or removes bindings.
- Interactive vertical swipe (Mission Control / App Expose), tracking-speed slider, smart zoom,
  "reset swipe" menu item.

## Risks

- Private event format can change with any macOS update: keep the probe, fall back to discrete.
- A crash mid-swipe cannot be cleaned up; a lost HID++ button-up is only covered by the watchdog.
- Raw XY divert: if Mos dies mid-hold the button may stay diverted until the mouse reconnects.
- Mac Mouse Fix's licence allows private use; this is an own implementation from documented
  constants, with credit in the source comments.
