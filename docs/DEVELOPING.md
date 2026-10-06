# Developing

A SwiftPM package with no Xcode project and no dependencies. The `.app` is assembled by the Makefile. The only stored state is the last input, in UserDefaults under `local.DefaultAliveCalculator`.

## Layout

| Path | What |
|---|---|
| `Sources/DefaultAliveCore/` | Everything testable: the math (`Projection`, `Breakevens`), units, parsing, formatting, taxes, the readout text, and the form's behavior (`CalculatorState`). |
| `Sources/DefaultAliveCalculator/` | The app: AppKit shell and key handling (`App.swift`), SwiftUI view (`CalculatorView`), tax checklist (`TaxPicker`), chart (`BalanceChart`), persistence, and the `--snapshot` / `--screenshot` / `--selftest` modes. |
| `Tests/` | Swift tests for the core. |
| `Resources/` | `Info.plist`, and `AppIcon.png`: the logo, on a transparent background. The build turns it into the app's `.icns`. |
| `design/` | Browser mock of the app, for trying UI changes before porting them. `model.js` is a JavaScript twin of the core. `presets.json` holds sample states and the expected text for each, checked by both test suites. |
| `docs/tax-research/` | The tax research behind `TaxPlaces.json` and the script that builds it. |

## Commands

| | |
|---|---|
| `make install` | Build, install to `~/Applications`, open. |
| `make` | Tests, build, snapshot, install, relaunch. |
| `make test` | Swift tests and the JavaScript twin's tests (needs Node). |
| `make preview` | Open the browser mock at http://127.0.0.1:8765/design/ (needs [uv](https://docs.astral.sh/uv/)). Each preset shows the mock beside the real app. |
| `make snapshot` | Render every preset through the real view → `build/snapshot.png`. |
| `make screenshots` | Regenerate the README images in `docs/screenshots/`. |
| `make selftest` | Drive the real app with key and mouse events → `build/selftest.txt`. Needs ~5s of idle keyboard. |
| `make uninstall` | Remove the app and its saved input. |

## Changing the UI

1. Mock it in `design/index.html` (and `design/model.js` if the math or wording changes). `make preview` reloads on save.
2. Port it. CSS variables in the mock map 1:1 onto `enum Style` in `CalculatorView.swift`; `model.js` functions have the same names as the Swift core. If text changes, update `expect` in `design/presets.json` first. It's the spec for both sides.
3. Run `make`. In the preview, the app column should now match the mock column.

## Tax data

`Sources/DefaultAliveCore/TaxPlaces.json` lists every state, DC, and the cities that tax a company before it's profitable. It's built by `node docs/tax-research/places.mjs` from the research in `docs/tax-research/taxes-2026-10.json` (one research agent per state, official sources, October 2026). The judgment calls, such as which thresholds exclude only the excess and treating Hawaii's excise tax like sales tax, are written down in `places.mjs`. The app compiles the JSON in, and the mock imports the same file.

To refresh it: rerun `docs/tax-research/workflow.js` (a Claude Code workflow), save the result as a new `taxes-YYYY-MM.json`, point `places.mjs` at it, run it, and review the diff.

## Notes

- **The two models must agree.** `model.js` mirrors the Swift core line for line, and `make test` checks both against `presets.json`. Rounding is explicit on both sides: ties away from zero for display, and toward the safe side for the "alive if" column (≥ rounds up, ≤ rounds down), so $241.04 reads "≥ $242".
- **Keys** are all handled in one NSEvent monitor in `App.swift`, not AppKit's key-view loop. Esc, C, the keypad Clear key, and ⌘⌫ (only with no box selected) clear everything. Tab and Return move between the four boxes (Shift goes back); Return also turns "163+5" into "168". Up and Down move between boxes too.
- **Commas and units are drawn, not typed.** The four boxes are an AppKit `NumberField`, because SwiftUI's TextField uses a private field editor and won't show rewritten text while editing. `GroupingFieldEditor` draws a grey comma in a kerned gap every three digits.
- **One empty box gets solved.** Each "alive if" threshold holds the other three numbers fixed and never reads its own, so with exactly one box empty the app can say what it needs to be.
- **Taxes** only include what's owed before profit: taxes on revenue, and fixed yearly fees. Income taxes are zero until breakeven, so they can't change the answer. Thresholds are checked against current revenue. Hints under taxes are converted back to the pre-tax numbers you'd type.
- **The tax checklist is a popover,** a separate window, so the key monitor never sees its keys: "c" types in the filter, and Esc closes it.
- **Dragging the profit dot** sets growth. As growth varies, the dot moves along a straight line, so the pointer is projected onto that line and stops at the zero line (the default-alive minimum).
- **$ growth** adds a fixed amount to the Revenue box's figure each period. Changing the Revenue box's unit re-expresses it.
- **Swift Charts** resolves `.secondary` against the accent color (blue gridlines), so the chart uses explicit `Color.primary.opacity(...)`. Edge axis labels must hang inward or Charts drops them.
- **Screenshots and snapshots** render offscreen at 2x, so they need no Screen Recording permission and never touch saved input. The README screenshots draw their own title bar, since AppKit draws an offscreen window's title bar as inactive.
