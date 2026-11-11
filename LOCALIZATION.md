# Localization

Scrollio ships in English only. The localization mechanism of the original project is
kept, so a language can be added again without touching the code.

## The two string catalogs

They must stay separate.

| File | Scope | Keys |
| --- | --- | --- |
| `Mos/Localizable.xcstrings` | Strings used from Swift with `NSLocalizedString` | Readable phrases (older keys) or identifiers that mirror code constants (`appExpose`, `categoryFunctionKeys`, the identifiers of `SystemShortcut.Shortcut`, and by area `general-*`, `scrolling-*`, `buttons-*`, `mouse-*`, `gesture-*` / `gestures-*`, `apps-*`, `about-*`, `preferences-*`, `main-menu-*`, `status-menu-*` / `status-item-*`, `intro-*`, `toast-*`) |
| `Mos/mul.lproj/Main.xcstrings` | The storyboard | Interface Builder object ids (`2AK-Pu-mot.title`) |

Rules:

- Never rename a key that code, saved settings or Interface Builder uses, and never edit
  an object id by hand.
- In Swift use `NSLocalizedString(_:comment:)`, not `String(localized:)`.
- English values in `Main.xcstrings` override the storyboard text, so a storyboard title
  is changed in both places.
- When a `SystemShortcut.Shortcut` is added, its `identifier` becomes a key in
  `Localizable.xcstrings`: menus and the Buttons pane show `NSLocalizedString(identifier, …)`.
- Keep modifier symbols as they are: "⌘ Command", "⌥ Option", "⌃ Control", "⇧ Shift".
- Product and feature names stay as they are: Scrollio, SmartShift, Logi Options+,
  MX Master, HID++, Mission Control.
- Edits made by a script must keep the catalog formatting byte-stable:
  `json.dumps(obj, ensure_ascii=False, indent=2, separators=(",", ": ")) + "\n"`.

## Adding a string

In code: add `NSLocalizedString("key", comment: "…")`, then add the key with its English
value to `Mos/Localizable.xcstrings` (building in Xcode extracts new keys).

In the storyboard: change `Mos/Base.lproj/Main.storyboard`, build, and fill in the new
object ids in `Mos/mul.lproj/Main.xcstrings`. When a UI element is deleted, remove its
stale entries.

Strings of the preference panes (all built in code), the sidebar, the main menu, the
status-bar menu and the Welcome Guide are also listed in
`MosTests/PreferencesLocalizationTests.swift`, one array per area (`generalKeys`,
`scrollingKeys`, `buttonsKeys`, `gesturesKeys`, `mouseKeys`, `appsKeys`,
`windowKeys`, `menuKeys`, `introKeys`; `keys` is their union; the `about-*` keys, the
header and the bottom of General, are in `generalKeys`). Add a new key to the array
of its area: several keys are built from variables in code, and a missing one would only
show up as the raw key in the UI.

## The test

`PreferencesLocalizationTests` checks, for every locale in its `locales` list (now
`["en"]`), that each listed key exists, is not empty and is not shown as the raw key, and
that every string code formats with `String(format:)` takes the arguments its call site
passes (the table `formatArguments`: key, then "@" for a String and "d" for an Int, in
order). When you format a new string, add its key and arguments to that table.

## Adding a language

1. Add the language to the project (`knownRegions` in `Mos.xcodeproj/project.pbxproj`, or
   Project > Info > Localizations in Xcode) for both catalogs.
2. Translate every key in both catalogs. Use the terms Apple uses in System Settings for
   system features.
3. Add the locale code to `PreferencesLocalizationTests.locales`.
4. Switch macOS to the language and walk through the Introduction window, every
   Preferences pane, the button recorder and the action menus, looking for clipped text.

## Checks

```bash
# The catalogs are valid JSON
python3 -m json.tool Mos/Localizable.xcstrings >/dev/null
python3 -m json.tool Mos/mul.lproj/Main.xcstrings >/dev/null

# Locales present in each catalog
python3 - <<'PY'
import json, pathlib
for path in ("Mos/Localizable.xcstrings", "Mos/mul.lproj/Main.xcstrings"):
    catalog = json.loads(pathlib.Path(path).read_text())
    locales = sorted({lang for row in catalog["strings"].values()
                     for lang in row.get("localizations", {})})
    print(path, ", ".join(locales))
PY
```
