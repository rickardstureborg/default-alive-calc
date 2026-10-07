@../docs/DEVELOPING.md

# Agent notes

## Working loop

- UI changes go through the browser mock first (`design/`), then the user's OK, then the Swift port, unless the user spelled out exactly what they want.
- Logic changes are test-first in `Tests/DefaultAliveCoreTests`. Wording or hint changes start in `expect` in `design/presets.json`, the spec for both `swift test` and `node --test`.
- Commit each finished piece on its own with a short lower-case message. Never push without asking.

## Seeing the app

`screencapture` needs Screen Recording and System Events keystrokes need Accessibility; this terminal has neither. Instead:

- Looks: `make snapshot`, then Read `build/snapshot.png` (rows = presets in `presets.json` order, columns light | dark, 2x, 16px gaps). Crop a row with `sips -c <h> <w> --cropOffset <y> 16`.
- The mock: `make preview-shot` → `build/preview.png` (whole page, mock beside app) and `build/preview-live.png`. One exact state: `node design/shot.mjs 'http://127.0.0.1:8765/design/?preset=dead&theme=light' out.png '#live-window'`. URL switches: `preset=`, `theme=light|dark`, `taxes=1`, `assumptions=1`, `picker=1`. Interaction tests: a throwaway CDP script in `$TMPDIR` (copy the Chrome setup from `shot.mjs`; use `--window-size=1200,1400`), deleted afterwards.
- Keys and mouse: `make selftest` → `build/selftest.txt`. It waits for 5s of no keyboard/mouse input, and reports `INTERRUPTED` (not FAILs) if the user takes focus mid-run; rerun when idle.

## Traps

- **Persisted keys**: `cash`, `expenses[Unit]`, `revenue[Unit]`, `growthPercent[Unit]`, `growthDollar[Unit]`, `growthLinear`, `taxesOn`, `taxPlaces`, `taxShares`, `chartShown`. Nothing else, and never window frames.
- **Focus** moves are `FocusRequest`s applied by `NumberField` itself (makeFirstResponder, then select), not SwiftUI focus. Forward selects all; backward and arrows park the cursor at the end. The Edit menu's Clear All shortcut is Esc because a ⌘⌫ menu shortcut would fire before the field's delete-to-start.
- **Selftest coordinates**: SwiftUI's `.global` space on this window starts at the window's top edge *including* the 28pt title bar; convert with `window.frame.height`. The profit dot is found through `SelfTestProbe`. The checklist popover fades out over a few hundred ms; check it's gone after ~1s, not 300ms.
- **Mock colors** were measured from snapshot pixels (TextField text is AppKit `textColor`, 100% black/white, not SwiftUI's 85%). Re-measure rather than guess.
- **Headless Chrome** `--screenshot` fires on a virtual-time budget; `shot.mjs` waits for `document.body.dataset.ready` instead.
- **Taxes**: per place, `rate` × share of revenue counted there, then `perYear`. A threshold is judged on current revenue: a cliff, or `excess` (only the amount above is taxed; always measured on revenue "there"). Sums run in catalog order on both sides so the last bit matches. Each place's default share comes from the research: population share for taxes sourced to customers, 100% for ones sourced to your office. Hawaii GET and New Mexico GRT are treated as pass-through like sales tax.
- **Checklist filter** (`TaxCatalog.matching` / `matchingPlaces`): every word typed must be in the place name or state name, or equal the state code. "Add all"/"Remove all" act on what's shown. A city shown without its state reads "Seattle, WA".
- **Solving one empty box**: empty boxes stand in as 0 in `readout(inputs, empty:)`. Two or more empty → "Enter at least three numbers"; any red box wins. With revenue empty, taxes are judged at revenue 0, so threshold taxes drop out of that answer.
- **$ growth** is linear in the period. An earlier version squared it ($50/wk read as $136k/yr). It's always MRR added per period, never tied to the Revenue box's unit: when it was, clicking Revenue's week/month/year rewrote the growth box. A unit toggle changes only its own box (`aUnitToggleChangesOnlyItsOwnBox`, and the selftest's toggle clicks).
- **`make`** kills and relaunches the installed app; input survives because it's saved on every keystroke.
