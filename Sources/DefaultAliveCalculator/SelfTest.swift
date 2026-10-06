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
            var interrupted: String?
            // Everything here needs the window to be key. If someone uses the Mac mid-run,
            // macOS hands focus to their app and every later check fails for that reason
            // alone; report that once instead of a pile of misleading FAILs.
            @MainActor func check(_ name: String, _ ok: Bool, _ detail: String) {
                guard interrupted == nil else { return }
                guard window.isKeyWindow else {
                    interrupted = name
                    return
                }
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
            @MainActor func click(_ point: NSPoint) async {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                        pressure: type == .leftMouseDown ? 1 : 0)!
                    NSApp.postEvent(event, atStart: false)
                }
                await settle()
            }
            @MainActor func mouse(_ type: NSEvent.EventType, _ point: NSPoint) async {
                let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                    pressure: type == .leftMouseUp ? 0 : 1)!
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
                ("Esc", 53, "\u{1b}", []), ("C", 8, "c", []), ("keypad Clear", 71, "\u{F739}", []),
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
            check("⌘C does not clear", model.state.field(.cash).text == "400k", "cash=\(model.state.field(.cash).text)")

            // ⌘⌫ inside a box: delete back to the start of that box only.
            (window.firstResponder as? NSTextView)?.setSelectedRange(NSRange(location: 2, length: 0))
            await key(51, "\u{7f}", .command)
            check("⌘⌫ in a box deletes to its start only", model.state.field(.cash).text == "0k" && model.state.field(.expenses).text == "80k",
                  "cash=\(model.state.field(.cash).text) expenses=\(model.state.field(.expenses).text)")

            // Clicking empty space deselects; then ⌘⌫ clears everything.
            model.state = state
            await settle()
            await click(NSPoint(x: 12, y: 12))
            check("click on background deselects", where_().row == "none", "at \(where_().row)")
            await key(51, "\u{7f}", .command)
            let empty = Row.allCases.allSatisfy { model.state.field($0).text.isEmpty }
            check("⌘⌫ with no box selected clears all", empty, "empty=\(empty)")
            await click(NSPoint(x: 12, y: 12))
            model.state = state
            await settle()
            await key(48, "\t")
            check("Tab with no box selected goes to cash", where_().row == "cash", "at \(where_().row)")

            // The background tap handler must not swallow clicks meant for a box. Expenses'
            // centre, from the layout: padding 20 + "alive if" header ~20 + cash row 28 +
            // spacing 10 + half a row; x is the field's middle, 400 − 20 − 72 − 10 − 60.
            let height = window.contentView?.bounds.height ?? 0
            await click(NSPoint(x: 238, y: height - 92))
            check("clicking a box still focuses it", where_().row == "expenses", "at \(where_().row)")

            // Arithmetic, typed key by key: live value, Tab keeps it, Return compacts it.
            await key(48, "\u{19}", .shift)
            (window.firstResponder as? NSTextView)?.selectAll(nil)
            for (code, ch) in [(18, "1"), (22, "6"), (20, "3"), (24, "+"), (23, "5")] as [(UInt16, String)] {
                await key(code, ch, ch == "+" ? .shift : [])
            }
            check("typing 163+5 counts as 168", model.state.field(.cash).text == "163+5" && model.state.inputs?.cash == 168,
                  "text \(model.state.field(.cash).text), value \(model.state.inputs?.cash ?? -1)")
            await key(48, "\t")
            check("Tab leaves the expression", model.state.field(.cash).text == "163+5", "cash=\(model.state.field(.cash).text)")
            await key(48, "\u{19}", .shift)
            await key(36, "\r")
            check("Return compacts it and moves on", model.state.field(.cash).text == "168" && where_().row == "expenses",
                  "cash=\(model.state.field(.cash).text) at \(where_().row)")

            // Arrows: Up/Down to the box above/below, cursor at the end, no wrapping.
            let arrows: [(String, UInt16, String, Bool, String)] = [
                ("Down", 125, "\u{F701}", true, "revenue"),
                ("Down", 125, "\u{F701}", true, "growth"),
                ("Down at the bottom stays", 125, "\u{F701}", true, "growth"),
                ("Up", 126, "\u{F700}", false, "revenue"),
                ("Up", 126, "\u{F700}", false, "expenses"),
                ("Up", 126, "\u{F700}", false, "cash"),
                ("Up at the top stays", 126, "\u{F700}", false, "cash"),
            ]
            for (name, code, chars, _, expected) in arrows {
                await key(code, chars, [.numericPad, .function])
                let (row, sel) = where_()
                let length = (model.state.field(rowFor(expected)).text as NSString).length
                check("\(name) → \(expected), cursor at end", row == expected && sel == NSRange(location: length, length: 0),
                      "at \(row), selection \(sel.location)+\(sel.length)")
            }

            // Thousands commas are drawn by the field editor, never stored: typed key by key in
            // cash (where the arrows left us).
            (window.firstResponder as? NSTextView)?.selectAll(nil)
            for (code, ch) in [(18, "1"), (22, "6"), (20, "3"), (29, "0"), (29, "0"), (29, "0"), (29, "0")] as [(UInt16, String)] {
                await key(code, ch)
            }
            let editor = window.firstResponder as? NSTextView
            let kerned = (0..<(editor?.textStorage?.length ?? 0)).filter { editor?.textStorage?.attribute(.kern, at: $0, effectiveRange: nil) != nil }
            check("typing 1630000 keeps the text raw, cursor at end",
                  model.state.field(.cash).text == "1630000" && editor?.string == "1630000" && where_().selection == NSRange(location: 7, length: 0),
                  "text \(model.state.field(.cash).text), box \(editor?.string ?? "-"), selection \(where_().selection.location)+\(where_().selection.length)")
            check("commas drawn after 1 and 1630", kerned == [0, 3], "comma gaps after characters \(kerned), editor \(editor.map { String(describing: type(of: $0)) } ?? "none")")
            // A picture of the box mid-edit, to eyeball the drawn commas.
            // The editing text view itself, at 2x: its own draw() puts the commas in.
            if let editor {
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(editor.bounds.width) * 2, pixelsHigh: Int(editor.bounds.height) * 2,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0)!
                rep.size = editor.bounds.size
                editor.cacheDisplay(in: editor.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output + ".editing.png"))
            }
            editor?.setSelectedRange(NSRange(location: 1, length: 0))
            await key(23, "5")
            check("typing mid-number keeps the cursor", model.state.field(.cash).text == "15630000" && where_().selection == NSRange(location: 2, length: 0),
                  "text \(model.state.field(.cash).text), selection \(where_().selection.location)+\(where_().selection.length)")
            await key(51, "\u{7f}")
            check("Backspace deletes a digit, never a comma", model.state.field(.cash).text == "1630000" && where_().selection == NSRange(location: 1, length: 0),
                  "text \(model.state.field(.cash).text), selection \(where_().selection.location)+\(where_().selection.length)")
            await key(21, "$", .shift)
            check("a typed $ is dropped (the box draws it)", model.state.field(.cash).text == "1630000" && where_().selection == NSRange(location: 1, length: 0),
                  "text \(model.state.field(.cash).text), selection \(where_().selection.location)+\(where_().selection.length)")

            // Dragging the chart's profitability dot sets growth and outlines the growth box.
            model.chartShown = true
            model.state = CalculatorState(input: RawInputs(cash: "1.2M", expenses: "80k", revenue: "20k", growth: "8"))
            try? await Task.sleep(for: .milliseconds(400))
            if let dot = SelfTestProbe.profitDot {
                // SwiftUI's global space runs top-down from the window's top edge, title bar
                // included; window coordinates run bottom-up. (Measured: converting with the
                // content height instead missed by exactly the 28pt title bar.)
                let start = NSPoint(x: dot.x, y: window.frame.height - dot.y)
                await mouse(.leftMouseDown, start)
                await mouse(.leftMouseDragged, NSPoint(x: start.x + 30, y: start.y - 15))
                let during = model.state.field(.growth).text
                check("dragging the dot right and down lowers growth, outline green",
                      (Double(during) ?? 99) < 8 && SelfTestProbe.growthOutline == "green",
                      "growth \(during), outline \(SelfTestProbe.growthOutline ?? "none")")
                await mouse(.leftMouseDragged, NSPoint(x: start.x + 400, y: start.y - 400))
                check("held at the zero line: the default-alive minimum, outline red",
                      model.state.field(.growth).text == "4.33" && SelfTestProbe.growthOutline == "red",
                      "growth \(model.state.field(.growth).text), outline \(SelfTestProbe.growthOutline ?? "none")")
                await mouse(.leftMouseUp, NSPoint(x: start.x + 400, y: start.y - 400))
                check("letting go keeps the growth and clears the outline",
                      model.state.field(.growth).text == "4.33" && SelfTestProbe.growthOutline == nil,
                      "growth \(model.state.field(.growth).text), outline \(SelfTestProbe.growthOutline ?? "none")")
            } else {
                check("profitability dot on the chart", false, "not found")
            }

            if let interrupted {
                lines.append("INTERRUPTED at \"\(interrupted)\": the window lost keyboard focus (someone used the Mac). Rerun when it is idle.")
            } else {
                lines.append(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
            }
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
