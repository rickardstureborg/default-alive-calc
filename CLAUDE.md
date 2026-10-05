# Default Alive Calculator

Native macOS calculator for PG's "default alive" test: SwiftPM, no Xcode project, no
dependencies. The only persisted state is the last input (UserDefaults, bundle id
`local.DefaultAliveCalculator`).

## Layout

- `Sources/DefaultAliveCore/`: pure math, parsing, formatting, `readout()` (all text under the divider). Unit-tested.
- `Sources/DefaultAliveCalculator/`: AppKit shell (`App.swift`), SwiftUI view (`CalculatorView.swift`, tokens in `enum Style`), `--snapshot` renderer (`Snapshot.swift`).
- `design/`: the browser mock. `index.html` (UI, CSS variables named like `Style`), `model.js` (JS twin of the core), `presets.json` (gallery states + the shared spec for readout text).

## Design loop (use this for any UI change)

1. **Mock it in the browser first.** Edit `design/index.html` (and `design/model.js` if behavior changes). Run `make preview-shot` and Read `build/preview.png`: the gallery puts each design tile beside the app's current rendering of the same preset, light and dark. The user watches the same page via `make preview`; it live-reloads on save, so don't restart the server.
2. **Get the user's OK on the mock** before touching Swift.
3. **Port it.** CSS variables map 1:1 onto `enum Style`; `model.js` functions map onto `DefaultAliveCore` with the same names. If wording changes, update `expect` in `design/presets.json`; it's the spec for both sides. Logic changes are test-first in `Tests/DefaultAliveCoreTests`.
4. **`make`**: Swift + node tests, build, refresh `build/snapshot.png`, reinstall to `~/Applications`, relaunch. Then `make preview-shot` again: the app columns should now match the design columns.

## Commands

| | |
|---|---|
| `make` | test → build → snapshot → install → relaunch (≈4s) |
| `make app` | same without tests |
| `make test` | `swift test` + `node --test design/model.test.mjs` |
| `make snapshot` | real SwiftUI view, every preset, light/dark → `build/snapshot.png` |
| `make preview` / `preview-serve` / `preview-stop` | browser mock at http://127.0.0.1:8765/design/ |
| `make preview-shot` | headless Chrome screenshot → `build/preview.png` |
| `make uninstall` | removes the app and its defaults |

## Traps

- **The two models must stay identical.** `model.js` is a line-for-line twin of the Swift core; `make test` checks both against `presets.json`. Rounding is explicit ties-away-from-zero on both sides because printf `%.1f` (ties-to-even) and JS `toFixed` (ties-up) disagree on exact ties like $1.25M.
- **Prototype-only code** in `model.js` (marked "not in Swift yet") has no Swift twin or parity test until it's ported.
- **Seeing the app**: `screencapture` needs Screen Recording permission, and System Events keystrokes need Automation/Accessibility. This terminal has neither. Use `make snapshot`, which renders offscreen and needs no permission. For keyboard behavior in the native app, ask the user to check by hand.
- **Claude in Chrome** may not be connected; `make preview-shot`, or a CDP script driving headless Chrome, works without it.
- **TextField text** is AppKit underneath: `NSColor.textColor` (100% black/white), not SwiftUI's 85% label color. The mock's colors were measured from snapshot pixels; re-measure rather than guess if they drift.
- **Running app**: `make` kills and relaunches it. Input survives because it's written to UserDefaults on every keystroke.
