import AppKit
import DefaultAliveCore

/// `--selftest <out.txt>` (via `make selftest`): drives the real window with synthetic key
/// events and writes PASS/FAIL lines. Events are posted to the app's own queue, so they
/// pass through the same NSEvent monitor as real typing, without the Accessibility or
/// Automation permission that System Events would need. Uses a model with no store, so
/// saved input is never touched.
@MainActor
enum SelfTest {
    static let state = CalculatorState(input: RawInputs(cash: "$400k", expenses: "80k", revenue: "20k", growth: "8%"))

    static func run(window: NSWindow, model: CalculatorModel, output: String) {
        Task { @MainActor in
            var lines: [String] = []
            var failures = 0
            @MainActor func check(_ name: String, _ ok: Bool, _ detail: String) {
                if !ok { failures += 1 }
                lines.append("\(ok ? "PASS" : "FAIL")  \(name)  [\(detail)]")
            }
            func settle() async { try? await Task.sleep(for: .milliseconds(150)) }
            @MainActor func key(_ code: UInt16, _ chars: String, _ mods: NSEvent.ModifierFlags = []) async {
                let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                    isARepeat: false, keyCode: code)!
                NSApp.postEvent(event, atStart: false)
                await settle()
            }
            /// Which box has the cursor (by its text, all distinct here) and what's selected.
            @MainActor func where_() -> (row: String, selection: NSRange) {
                guard let editor = window.firstResponder as? NSTextView else { return ("none", NSRange()) }
                let rows: [(String, Row)] = [("cash", .cash), ("expenses", .expenses), ("revenue", .revenue), ("growth", .growth)]
                let row = rows.first { model.state.field($0.1).text == editor.string }?.0 ?? "?(\(editor.string))"
                return (row, editor.selectedRange())
            }

            try? await Task.sleep(for: .milliseconds(600))
            check("window is key", window.isKeyWindow, "isKeyWindow=\(window.isKeyWindow)")
            check("starts in cash", where_().row == "cash", where_().row)

            let tab: UInt16 = 48, ret: UInt16 = 36
            let steps: [(String, UInt16, String, NSEvent.ModifierFlags, String, Bool)] = [
                ("Tab", tab, "\t", [], "expenses", true),
                ("Return", ret, "\r", [], "revenue", true),
                ("Tab", tab, "\t", [], "growth", true),
                ("Tab wraps", tab, "\t", [], "cash", true),
                ("Shift-Tab wraps", tab, "\u{19}", .shift, "growth", false),
                ("Shift-Return", ret, "\r", .shift, "revenue", false),
                ("Shift-Tab", tab, "\u{19}", .shift, "expenses", false),
            ]
            for (name, code, chars, mods, expected, forward) in steps {
                await key(code, chars, mods)
                let (row, sel) = where_()
                let length = (model.state.field(rowFor(expected)).text as NSString).length
                let selectionOK = forward ? sel == NSRange(location: 0, length: length) : sel == NSRange(location: length, length: 0)
                check("\(name) → \(expected), \(forward ? "all selected" : "cursor at end")",
                      row == expected && selectionOK, "at \(row), selection \(sel.location)+\(sel.length), text \"\(model.state.field(rowFor(expected)).text)\"")
            }

            let clears: [(String, UInt16, String, NSEvent.ModifierFlags)] = [
                ("Esc", 53, "\u{1b}", []), ("C", 8, "c", []), ("⌘⌫", 51, "\u{7f}", .command),
            ]
            for (name, code, chars, mods) in clears {
                model.state = state
                await settle()
                await key(code, chars, mods)
                let empty = Row.allCases.allSatisfy { model.state.field($0).text.isEmpty }
                check("\(name) clears all, cursor to cash", empty && where_().row != "none", "empty=\(empty) at \(where_().row)")
            }
            model.state = state
            await settle()
            await key(8, "c", .command)
            check("⌘C does not clear", model.state.field(.cash).text == "$400k", "cash=\(model.state.field(.cash).text)")

            lines.append(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
            try? lines.joined(separator: "\n").appending("\n").write(toFile: output, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    private static func rowFor(_ name: String) -> Row {
        switch name {
        case "cash": .cash
        case "expenses": .expenses
        case "revenue": .revenue
        default: .growth
        }
    }
}
