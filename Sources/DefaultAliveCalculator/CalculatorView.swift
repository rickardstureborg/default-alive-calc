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
    /// Not persisted: the assumptions always start closed.
    @State private var assumptionsOpen: Bool

    /// `assumptionsOpen` is only for `--snapshot`; the app always starts with them closed.
    init(model: CalculatorModel, assumptionsOpen: Bool = false) {
        self.model = model
        _assumptionsOpen = State(initialValue: assumptionsOpen)
    }

    // No units in prompts: the box draws "$" or "%" itself.
    private static let prompts: [Row: String] = [.cash: "1.2M", .expenses: "80k", .revenue: "20k"]
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
            taxes.padding(.top, 12)
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
                if model.chartShown, let inputs = model.state.chartInputs, let curve = balanceCurve(inputs) {
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
            let arrow = note.userInfo?["arrow"] as? Bool == true
            if note.userInfo?["commit"] as? Bool == true, let row = focus { model.state.commit(row) }
            let target = focus.map { arrow ? $0.stepped(down: forward) : $0.moved(forward: forward) } ?? .cash
            // At the top or bottom an arrow has nowhere to go; leave the cursor where it is.
            guard target != focus else { return }
            let previous = (NSApp.keyWindow?.firstResponder as? NSTextView)?.delegate
            focus = target
            // Tab and Return forward select the box to overwrite; going back, and arrows,
            // park the cursor at the end.
            Self.placeCursor(selectAll: forward && !arrow, awayFrom: previous)
        }
    }

    /// Forward selects the whole box (to overwrite); backward parks the cursor at the end
    /// (to fix up what you just typed). SwiftUI moves first responder on a later run-loop
    /// pass, and AppKit selects all when it does, so a selection set right away lands on the
    /// old box and then gets overridden (`make selftest` caught exactly that). Wait until the
    /// shared field editor belongs to a different box, then set it.
    private static func placeCursor(selectAll: Bool, awayFrom previous: NSTextViewDelegate?, tries: Int = 0) {
        DispatchQueue.main.async {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.delegate !== previous else {
                if tries < 20 { placeCursor(selectAll: selectAll, awayFrom: previous, tries: tries + 1) }
                return
            }
            if selectAll {
                editor.selectAll(nil)
            } else {
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            }
        }
    }

    // MARK: Taxes

    /// Ticking the box only turns taxes on; the italic link opens and closes the assumptions.
    private var taxes: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Include taxes", isOn: $model.state.taxesOn)
                    .toggleStyle(.checkbox)
                    .font(.system(size: Style.labelSize))
                    .focusable(false)
                Button { assumptionsOpen.toggle() } label: {
                    Text("assumptions").italic().underline(true, pattern: .dot, color: .secondary)
                }
                .buttonStyle(.plain)
                .font(.system(size: Style.hintSize))
                .foregroundStyle(.secondary)
                .focusable(false)
                Spacer(minLength: 0)
                Text(model.state.taxSummary)
                    .font(.system(size: Style.hintSize).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            if assumptionsOpen { assumptions.padding(.leading, 22) }
        }
    }

    private var assumptions: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                assumption("Oakland business tax", "0.36% of gross receipts (Class F, no small-business exemption). 100% is the upper bound.")
                share($model.state.oaklandShare)
            }
            GridRow {
                assumption("Washington B&O", "nothing under about $140k a year of Washington receipts; above it, 0.471% of them.")
                share($model.state.washingtonShare)
            }
            GridRow {
                assumption("Delaware", "$400 franchise tax (assumed par value method) + $50 annual report.")
                Text("$450/yr").gridColumnAlignment(.trailing)
            }
            Text("Not counted: income taxes (federal 21%, California 8.84% of profit) are zero until you're profitable, so they can't change the verdict. Enter revenue net of sales tax, and count payroll taxes in expenses.")
                .gridCellColumns(2)
                .padding(.top, 2)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func assumption(_ name: String, _ detail: String) -> some View {
        (Text(name).bold().foregroundStyle(.primary) + Text(" · " + detail))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A share of revenue, in percent. Mouse-only like the other secondary controls: Tab
    /// and Return still cycle just the four main boxes.
    private func share(_ text: Binding<String>) -> some View {
        HStack(spacing: 2) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .foregroundStyle(parsePercent(text.wrappedValue) == nil ? Style.dead : Color.primary)
                .padding(.horizontal, 5)
                .frame(width: 38, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
            Text("%")
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
        let text = Binding(get: { model.state.field(row).text }, set: { typed in
            // edit() regroups thousands and drops "$"/"%" live. When that rewrites the text,
            // SwiftUI pushes it into the field editor and the cursor jumps to the end, so put
            // it back where it was among the surviving characters.
            let editor = NSApp.keyWindow?.firstResponder as? NSTextView
            let caret = editor?.selectedRange().location
            model.state.edit(row, text: typed)
            let shown = model.state.field(row).text
            if shown != typed, let editor, let caret {
                Self.placeCaret(editor, at: caretAfterNormalizing(typed, caret: caret, shown), once: shown)
            }
        })
        let prompt = row == .growth ? (model.state.linear ? "1.6k" : "8") : Self.prompts[row] ?? ""
        let unit = row == .growth && !model.state.linear ? "%" : "$"
        return TextField(prompt, text: text, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: Style.fieldSize).monospacedDigit())
            // Empty isn't an error, just incomplete; only flag text that can't be a number.
            .foregroundStyle(model.state.isInvalid(row) ? Style.dead : Color.primary)
            .focused($focus, equals: row)
            .padding(.leading, 22)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(width: Style.fieldWidth)
            .background(RoundedRectangle(cornerRadius: Style.fieldRadius).fill(.quaternary))
            // The unit is drawn, not typed, so the text is just the number.
            .overlay(alignment: .leading) {
                Text(unit)
                    .font(.system(size: Style.fieldSize).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .allowsHitTesting(false)
            }
    }

    /// Once the field editor shows `text`, put the cursor at `location`.
    private static func placeCaret(_ editor: NSTextView, at location: Int, once text: String, tries: Int = 0) {
        DispatchQueue.main.async {
            guard editor.string == text else {
                if tries < 20 { placeCaret(editor, at: location, once: text, tries: tries + 1) }
                return
            }
            editor.setSelectedRange(NSRange(location: location, length: 0))
        }
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
