import DefaultAliveCore
import SwiftUI

/// Layout tokens. design/index.html defines the same names as CSS variables
/// (--width, --padding, …), so a design approved in the browser ports by copying numbers.
enum Style {
    static let width: CGFloat = 400
    static let padding: CGFloat = 20
    static let rowSpacing: CGFloat = 10
    static let labelSize: CGFloat = 13
    static let fieldSize: CGFloat = 15
    static let fieldWidth: CGFloat = 120
    static let fieldRadius: CGFloat = 6
    static let hintWidth: CGFloat = 72
    static let hintSize: CGFloat = 12
    static let dividerSpacing: CGFloat = 16
    static let verdictSize: CGFloat = 22
    static let detailSize: CGFloat = 12
    static let chartHeight: CGFloat = 120
    static let alive = Color.green
    static let dead = Color.red
}

extension Notification.Name {
    static let clearInputs = Notification.Name("clearInputs")
    /// userInfo["forward"]: Bool. Tab/Return forward, with Shift backward.
    static let moveFocus = Notification.Name("moveFocus")
}

struct CalculatorForm: View {
    @Bindable var model: CalculatorModel
    @FocusState private var focus: Row?

    private static let prompts: [Row: String] = [.cash: "$1.2M", .expenses: "80k", .revenue: "20k"]
    private static let help: [Row: String] = [
        .cash: "Default alive with at least this much cash, everything else unchanged",
        .expenses: "Default alive with expenses at or below this, everything else unchanged",
        .revenue: "Default alive with revenue at or above this, everything else unchanged",
        .growth: "Default alive with growth at or above this, everything else unchanged",
    ]

    var body: some View {
        let r = model.state.readout(now: .now)
        VStack(spacing: 0) {
            Text("alive if")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 6)
            VStack(spacing: Style.rowSpacing) {
                ForEach(Row.allCases, id: \.self) { row in
                    HStack(spacing: 10) {
                        label(row).font(.system(size: Style.labelSize))
                        Spacer(minLength: 0)
                        field(row)
                        Text(r.hints[row])
                            .font(.system(size: Style.hintSize).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: Style.hintWidth, alignment: .trailing)
                            .help(Self.help[row] ?? "")
                    }
                }
            }
            Divider().padding(.vertical, Style.dividerSpacing)
            result(r)
            if r.tone != .neutral {
                // Mouse-only, like the unit toggles: Tab and Return stay in the boxes.
                Button(model.chartShown ? "Hide chart" : "Show chart") { model.chartShown.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .focusable(false)
                    .padding(.top, 10)
                if model.chartShown, let inputs = model.state.inputs, let curve = balanceCurve(inputs) {
                    BalanceChart(curve: curve, now: .now).padding(.top, 8)
                }
            }
        }
        .padding(Style.padding)
        .frame(width: Style.width)
        // Clicking empty space takes the cursor out of the boxes, as in a browser. That's
        // the "no box selected" state where ⌘⌫ clears everything.
        .contentShape(Rectangle())
        .onTapGesture { focus = nil }
        .onAppear { focus = .cash }
        .onReceive(NotificationCenter.default.publisher(for: .clearInputs)) { _ in
            model.state.clear()
            focus = .cash
        }
        .onReceive(NotificationCenter.default.publisher(for: .moveFocus)) { note in
            let forward = note.userInfo?["forward"] as? Bool ?? true
            let previous = (NSApp.keyWindow?.firstResponder as? NSTextView)?.delegate
            focus = focus?.moved(forward: forward) ?? .cash
            Self.placeCursor(forward: forward, awayFrom: previous)
        }
    }

    /// Forward selects the whole box (to overwrite); backward parks the cursor at the end
    /// (to fix up what you just typed). SwiftUI moves first responder on a later run-loop
    /// pass, and AppKit selects all when it does, so a selection set right away lands on the
    /// old box and then gets overridden (`make selftest` caught exactly that). Wait until the
    /// shared field editor belongs to a different box, then set it.
    private static func placeCursor(forward: Bool, awayFrom previous: NSTextViewDelegate?, tries: Int = 0) {
        DispatchQueue.main.async {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.delegate !== previous else {
                if tries < 20 { placeCursor(forward: forward, awayFrom: previous, tries: tries + 1) }
                return
            }
            if forward {
                editor.selectAll(nil)
            } else {
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            }
        }
    }

    // MARK: Labels with clickable units

    @ViewBuilder
    private func label(_ row: Row) -> some View {
        switch row {
        case .cash:
            Text("Cash balance")
        case .expenses:
            HStack(spacing: 0) { Text("Expenses / "); unitToggle(.expenses) }
        case .revenue:
            HStack(spacing: 0) { Text("Revenue / "); unitToggle(.revenue) }
        case .growth:
            HStack(spacing: 0) {
                toggle(model.state.linear ? "$" : "%",
                       help: model.state.linear ? "Switch to % (compounding) growth" : "Switch to $ (linear) growth") {
                    model.state.toggleGrowthKind()
                }
                Text(" Growth / ")
                unitToggle(.growth)
            }
        }
    }

    private func unitToggle(_ row: Row) -> some View {
        let unit = model.state.field(row).unit
        return toggle(unit.rawValue, help: "Switch to per \(unit.next.rawValue)") { model.state.cycleUnit(row) }
    }

    /// A word in a label that changes something when clicked: dotted underline, and never a
    /// Tab stop.
    private func toggle(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).underline(true, pattern: .dot, color: .secondary)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }

    // MARK: Fields

    private func field(_ row: Row) -> some View {
        let text = Binding(get: { model.state.field(row).text }, set: { model.state.edit(row, text: $0) })
        let prompt = row == .growth ? (model.state.linear ? "$1.6k" : "8%") : Self.prompts[row] ?? ""
        return TextField(prompt, text: text, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: Style.fieldSize).monospacedDigit())
            // Empty isn't an error, just incomplete; only flag text that can't be a number.
            .foregroundStyle(model.state.isInvalid(row) ? Style.dead : Color.primary)
            .focused($focus, equals: row)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: Style.fieldWidth)
            .background(RoundedRectangle(cornerRadius: Style.fieldRadius).fill(.quaternary))
    }

    // MARK: Result

    private func result(_ r: Readout) -> some View {
        let color: Color = switch r.tone {
        case .alive: Style.alive
        case .dead: Style.dead
        case .neutral: .secondary
        }
        // Always three lines (" " holds an empty one open) so the window never changes
        // height as you type.
        return VStack(spacing: 4) {
            Text(r.headline)
                .font(.system(size: Style.verdictSize, weight: .bold))
                .tracking(1)
                .foregroundStyle(color)
                .padding(.bottom, 2)
            Text(r.line1.isEmpty ? " " : r.line1)
            Text(r.line2.isEmpty ? " " : r.line2)
        }
        .font(.system(size: Style.detailSize).monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
