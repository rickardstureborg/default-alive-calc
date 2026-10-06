# Default Alive Calculator

Native macOS calculator for PG's "default alive" test: SwiftPM, no Xcode project, no
dependencies. The only persisted state is the last input (UserDefaults, bundle id
`local.DefaultAliveCalculator`): each box's text and unit (`cash`, `expenses[Unit]`,
`revenue[Unit]`, `growthPercent[Unit]`, `growthDollar[Unit]`), `growthLinear`, `taxesOn`,
`oaklandShare`, `washingtonShare`, `chartShown`.

## Layout

- `Sources/DefaultAliveCore/`: everything testable. `Projection` (compounding + linear), `Units`, `Breakevens` (the "alive if" column), `Taxes`, `Formatting`, `Parsing` (numbers + arithmetic), `Readout` (all text under the divider + hints), `BalanceCurve` (chart data), `CalculatorState` (the form's behavior: unit cycling, separate %/$ growth boxes, taxes, commit, clear).
- `Sources/DefaultAliveCalculator/`: AppKit shell + key monitor (`App.swift`), persistence (`CalculatorModel`), SwiftUI view (`CalculatorView.swift`, tokens in `enum Style`), Swift Charts (`BalanceChart`), `--snapshot` (`Snapshot.swift`), `--selftest` (`SelfTest.swift`).
- `design/`: the browser mock. `index.html` (UI, CSS variables named like `Style`), `model.js` (JS twin of the core), `presets.json` (gallery states + shared spec for readout text and hints), `shot.mjs` (headless screenshots).

## Design loop (use this for any UI change)

1. **Mock it in the browser first.** Edit `design/index.html` (and `design/model.js` if behavior changes). Run `make preview-shot` and Read `build/preview.png` (whole page: each design tile beside the app's current rendering, light and dark) or `build/preview-live.png`. For one exact state: `node design/shot.mjs 'http://127.0.0.1:8765/design/?preset=dead&theme=light' out.png '#live-window'`. The user watches the same page via `make preview`; it live-reloads on save.
2. **Get the user's OK on the mock** before touching Swift, unless they've spelled out exactly what they want.
3. **Port it.** CSS variables map 1:1 onto `enum Style`; `model.js` functions map onto `DefaultAliveCore` with the same names. If wording or hints change, update `expect` in `design/presets.json`; it's the spec for both sides. Logic changes are test-first in `Tests/DefaultAliveCoreTests`.
4. **`make`**: Swift + node tests, build, refresh `build/snapshot.png`, reinstall to `~/Applications`, relaunch. Then `make preview-shot` again: the app columns should match the design columns. Keyboard changes: `make selftest`.

## Commands

| | |
|---|---|
| `make` | test → build → snapshot → install → relaunch |
| `make app` | same without tests |
| `make test` | `swift test` + `node --test design/model.test.mjs` |
| `make snapshot` | real SwiftUI view, every preset, light/dark → `build/snapshot.png` (always 2x) |
| `make selftest` | real key events through the app's own queue → `build/selftest.txt` |
| `make preview` / `preview-serve` / `preview-stop` | browser mock at http://127.0.0.1:8765/design/ |
| `make preview-shot` | headless Chrome → `build/preview.png`, `build/preview-live.png` |
| `make uninstall` | removes the app and its defaults |

## Traps

- **The two models must stay identical.** `model.js` is a line-for-line twin of the Swift core; `make test` checks both against `presets.json`. Rounding is explicit on both sides: ties away from zero for display, and toward the safe side for hints ("≥" up, "≤" down; $241.04 needed must read "≥ $242").
- **Seeing the app**: `screencapture` needs Screen Recording and System Events keystrokes need Automation/Accessibility; this terminal has neither. Use `make snapshot` for looks and `make selftest` for keys (both permission-free and never touch saved input; selftest flashes a second window for ~2s).
- **Keyboard**: all handled in the NSEvent monitor in `App.swift`, not AppKit's key-view loop (which would also stop on the unit buttons when keyboard navigation is on). Clear all: Esc, C, keypad Clear (keyCode 71), or ⌘⌫ only when no box has the cursor; inside a box ⌘⌫ passes through to delete-to-start, which is why the Edit menu's Clear All shortcut is Esc (a ⌘⌫ menu shortcut would fire first). Tab / Return: next box, Shift for previous, wrapping; Return also compacts an expression ("163+5" → "168"), Tab doesn't. Forward selects all, backward parks the cursor at the end; SwiftUI moves first responder a run-loop pass later, so `placeCursor` waits for the field editor to change hands. Clicking empty space deselects (`onTapGesture` on the form; selftest checks boxes still take clicks).
- **Boxes take arithmetic**: `evaluate()` in Parsing.swift / model.js. Unary minus only at the start or after "(", so "--5" stays invalid.
- **Taxes** (`Taxes.swift` / model.js `withTaxes`): only taxes that bite before profitability (Oakland's business tax on receipts, Washington's B&O past its small business credit, Delaware's fixed $450); income taxes are zero until breakeven so they can't change the verdict. Rates carry their source and check date in comments; re-check them yearly. Hints under taxes are converted back to pre-tax numbers (`Taxed.gross`).
- **Swift Charts colors**: `.secondary` / `.quaternary` resolve against the accent color there (blue gridlines). Use explicit `Color.primary.opacity(...)`.
- **Axis edge labels** must hang inward (`AxisValueLabel(anchor:)`), or Charts drops the "0" and truncates the last label.
- **TextField text** is AppKit underneath: `NSColor.textColor` (100% black/white), not SwiftUI's 85% label color. The mock's colors were measured from snapshot pixels; re-measure rather than guess if they drift.
- **Screenshots**: Chrome's `--headless --screenshot` fires on a virtual-time budget and caught the page before the gallery decoded; `shot.mjs` waits for `document.body.dataset.ready`. The snapshot is pinned to 2x because the render scale otherwise follows the main display (1x on the external monitor).
- **Running app**: `make` kills and relaunches it. Input survives because it's written to UserDefaults on every keystroke.
