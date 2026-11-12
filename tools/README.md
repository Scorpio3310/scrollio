# Developer tools

Hand-run tools from the original project, kept because they still match this code. They
are not part of any Xcode target. Run them from the repository root. Their comments are
in Chinese, as the original project wrote them.

## `hidpp/`: HID++ probes

Swift scripts that talk HID++ 2.0 to a Logitech mouse directly, as `Mos/Logi/` does over
Bluetooth (device index `0xFF`, divert flags `0x03`). Each opens the first Logitech
device (vendor `0x046D`) connected over **Bluetooth** (not through a receiver), sends
requests and prints the answers.

```bash
swift tools/hidpp/probe.swift
```

| Script | What it does |
| --- | --- |
| `probe.swift` | Ways of sending a request (with and without the report ID, three device indexes), a ping, a request while it holds the device exclusively, then 10 s of listening. |
| `full-test.swift` | Ping, feature discovery, name, battery, the controls of feature `0x1B04`; asks to divert every control that can be diverted, prints the presses for 20 s, gives them back. |
| `divert-debug.swift` | Diverts the controls one at a time, reads back their state, prints the presses for 10 s, gives them back. |
| `divert-fix.swift` | Tries four ways of diverting the SmartShift (mode shift) button, prints its presses for 10 s, gives it back. |
| `undivert-test.swift` | Diverts the SmartShift button and tries four ways of giving it back. |
| `verify-final.swift` | Diverts the controls with the flags Scrollio uses, prints the presses for 15 s, gives them back. |

**They change the mouse.** Every script but `probe.swift` diverts buttons: until it gives
them back, those buttons send their presses to the script and nothing to macOS. So:

- Never run a probe while Scrollio runs: quit it (and Logi Options+) first. A probe opens
  the same HID device through which Scrollio manages the mouse and diverts the buttons
  that have actions, and a divert or a give-back by the probe changes that without
  Scrollio knowing.
- If a script stops early (Ctrl-C, an error, a mouse that does not answer), the buttons
  it diverted stay diverted. Switching the mouse off and on gives them back.
- `probe.swift` holds the device exclusively for a moment: the mouse's input does not
  reach macOS meanwhile.

## `regression/`: toast harness

`toast-regression-tests.swift` checks the toast component's layout, stacking, visibility
rules and wrap width. It is compiled with four of the app's files, outside the test
target:

```bash
mkdir -p build
swiftc -parse-as-library \
  Mos/Components/Toast/ToastLayout.swift Mos/Components/Toast/ToastVisibilityRules.swift \
  Mos/Components/Toast/ToastContentView.swift Mos/Components/Toast/ToastStorage.swift \
  tools/regression/toast-regression-tests.swift -o build/toast-regression-tests
build/toast-regression-tests    # prints "toast regression tests passed"
```

A command-line tool has no bundle identifier, so the harness writes the toast's stored
wrap width to the preferences domain `app.toast` of the user who runs it.
