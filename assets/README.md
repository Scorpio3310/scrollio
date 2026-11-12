# Assets

The pictures of the repository's `README.md`. Nothing here is loaded by the app: run-time
images belong in `Scrollio/Assets.xcassets`, and the app icon is `Scrollio/AppIcon.icon`
(an Icon Composer file).

`readme/`:

- `app-icon.png`: the app icon, from the `AppIcon.icns` of a build.
- `<pane>-light.png` and `<pane>-dark.png` (`scrolling`, `buttons`, `gestures`, `mouse`,
  `welcome-guide`): the panes and a Welcome Guide step, light and dark, at 2x. They are
  drawn by `PreferencesWindowRenderTests.testRenderReadmePictures` and
  `WelcomeGuideRenderTests.testRenderReadmePicture`, which write them as
  `readme-<pane>-<appearance>.png` when `TEST_RUNNER_SCROLLIO_SHOTS_DIR` is set; the
  first of the two says how to render them with the numbers in US format. Only the
  tests' sample data appears in them.
