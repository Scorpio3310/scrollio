# Developer tools

Hand-run diagnostics and regression harnesses. They are not part of any Xcode target.

- `hidpp/`: Logitech HID++ probing, divert, undivert and verification scripts. They talk
  to a real mouse: run them only when you mean to.
- `regression/`: a small standalone harness that compiles selected app components
  outside the Xcode test target.

Run scripts from the repository root unless a script says otherwise.
