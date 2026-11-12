# Contributing

Scrollio is one person's project, made in spare time and for non-commercial use. This is
what you can expect.

- **Issues are welcome.** A report helps most when it says which macOS, which mouse and how
  it is connected (Bluetooth, a Logitech receiver, a cable), what you did, what you
  expected, and what the log says around that moment (README, "Diagnostics"). Read the log
  before you paste it: its `logi` lines carry the name of your mouse.
- **Pull requests are read, but may wait.** There is no promise when, and not every one
  will be merged. Before a larger change, open an issue and ask whether it fits.
- **A security problem does not go into an issue.** See [SECURITY.md](SECURITY.md).
- **Nothing about Scrollio belongs in the Mos repository.** Scrollio is a fork; its bugs
  are not Mos's. Do not open issues or pull requests about Scrollio there.

## If you send a change

- [AGENTS.md](AGENTS.md) has the rules of this code for people and for coding agents:
  how to build and test, what never to do with signing, the module boundaries, the
  strings.
- Build with your own signing team through `Local.xcconfig` (README, "Build from
  source"), not by changing the project.
- Run the tests of what you changed and `scripts/qa/lint-logi-boundary.sh`. A bug fix
  comes with a test that fails without it.
- Say in the pull request what you tried on a real Mac or mouse and what you could not
  try.

## Licence

Scrollio is licensed under CC BY-NC 4.0, because Mos is ([LICENSE](LICENSE)). What you
contribute is published under the same licence.
