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
    /// `--selftest` only: open the assumptions and the tax checklist.
    static let openTaxPicker = Notification.Name("openTaxPicker")
}

struct CalculatorForm: View {
    @Bindable var model: CalculatorModel
    /// Which box has the cursor, kept current by NumberField.
    @State private var focus: Row?
    @State private var focusRequest: FocusRequest?
    /// Set while the chart's profitability dot is dragged: outlines the growth box it sets.
    @State private var dragOutline: Color? {
        didSet { SelfTestProbe.growthOutline = dragOutline == nil ? nil : dragOutline == Style.dead ? "red" : "green" }
    }
    /// Not persisted: the assumptions always start closed.
    @State private var assumptionsOpen: Bool
    @State private var pickerOpen = false

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
            if r.tone != .neutral, model.chartShown, let inputs = model.state.chartInputs, let curve = balanceCurve(inputs) {
                BalanceChart(curve: curve, inputs: inputs, revenueUnit: model.state.revenue.unit, now: .now) { drag in
                    // Dragging the profitability dot sets growth; the growth box is outlined
                    // while it does: green, red once held at the default-alive limit.
                    if let drag {
                        model.state.setGrowth(monthly: model.state.growthFromChart(drag.monthlyGrowth))
                        dragOutline = drag.pinned ? Style.dead : Style.alive
                    } else {
                        dragOutline = nil
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(Style.padding)
        .frame(width: Style.width)
        // Clicking empty space takes the cursor out of the boxes, as in a browser. That's
        // the "no box selected" state where ⌘⌫ clears everything.
        .contentShape(Rectangle())
        .onTapGesture { request(nil) }
        .onAppear { request(.cash) }
        .onReceive(NotificationCenter.default.publisher(for: .clearInputs)) { _ in
            model.state.clear()
            request(.cash)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTaxPicker)) { _ in
            assumptionsOpen = true
            // The popover anchors on "Modify included locations", which only exists once the
            // assumptions have been laid out.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                pickerOpen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .moveFocus)) { note in
            let forward = note.userInfo?["forward"] as? Bool ?? true
            let arrow = note.userInfo?["arrow"] as? Bool == true
            if note.userInfo?["commit"] as? Bool == true, let row = focus { model.state.commit(row) }
            let target = focus.map { arrow ? $0.stepped(down: forward) : $0.moved(forward: forward) } ?? .cash
            // At the top or bottom an arrow has nowhere to go; leave the cursor where it is.
            guard target != focus else { return }
            // Tab and Return forward select the box to overwrite; going back, and arrows,
            // park the cursor at the end.
            request(target, selectAll: forward && !arrow)
        }
    }

    /// Move the cursor to `row` (nil: out of every box). NumberField applies it.
    private func request(_ row: Row?, selectAll: Bool = false) {
        focusRequest = FocusRequest(row: row, selectAll: selectAll, serial: (focusRequest?.serial ?? 0) + 1)
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
                // The size of the tax effect only shows with the assumptions it summarizes.
                if assumptionsOpen {
                    Text(model.state.taxSummary)
                        .font(.system(size: Style.hintSize).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            if assumptionsOpen { assumptions.padding(.leading, 22) }
        }
    }

    /// Past this many places ("Add all" makes 148) the list scrolls instead of stretching
    /// the window off the screen.
    private static let placesBeforeScrolling = 8
    private static let placesScrollHeight: CGFloat = 200

    /// One row per place you're in: name and what it costs (the full assumption on hover),
    /// your share of revenue there if it taxes receipts, and a remove link. Then "Modify
    /// included locations", which opens the checklist of every state and city.
    private var assumptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.state.taxPlaces.count > Self.placesBeforeScrolling {
                ScrollView { placeGrid }.frame(height: Self.placesScrollHeight)
            } else {
                placeGrid
            }
            link("Modify included locations") { pickerOpen.toggle() }
                .popover(isPresented: $pickerOpen, arrowEdge: .bottom) { TaxPicker(state: $model.state) }
            Text("Not counted: income taxes are zero until you're profitable, so they can't change the verdict. Enter revenue net of sales taxes (including Hawaii's and New Mexico's gross receipts taxes, which are itemized like sales tax), and count payroll taxes in expenses.")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Rows rather than a Grid: a Grid sized its text column to about half the width here
    /// and left the right quarter of the window empty, wrapping every name early. The share
    /// box gets a fixed slot so the boxes and remove links line up.
    private var placeGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.state.taxPlaces.compactMap(TaxCatalog.place)) { place in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    (Text(place.name).bold().foregroundStyle(.primary)
                        + Text(place.local ? ", \(place.state)" : "")
                        + Text(" · " + placeSummary(place)))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(place.note)
                    Group {
                        if place.rate > 0 { share(place) } else { Color.clear.frame(height: 0) }
                    }
                    .frame(width: 52, alignment: .trailing)
                    link("remove") { model.state.setTaxPlace(place.id, included: false) }
                }
            }
        }
    }

    /// The share of revenue counted to a place, in percent. Mouse-only like the other
    /// secondary controls: Tab and Return still cycle just the four main boxes.
    private func share(_ place: TaxPlace) -> some View {
        let text = Binding(get: { model.state.shareText(place.id) }, set: { model.state.taxShares[place.id] = $0 })
        return HStack(spacing: 2) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .foregroundStyle(model.state.isInvalidShare(place.id) ? Style.dead : Color.primary)
                .padding(.horizontal, 5)
                .frame(width: 38, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
            Text("%")
        }
        .help("Your share of revenue counted to \(place.name)")
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
            // For `make selftest`, which clicks each toggle.
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { SelfTestProbe.unitToggles[row] = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { SelfTestProbe.unitToggles[row] = geo.frame(in: .global) }
            })
    }

    /// "remove", "Modify included locations": secondary text with a dotted underline, never a
    /// Tab stop.
    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).underline(true, pattern: .dot, color: .secondary)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .focusable(false)
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
        let prompt = row == .growth ? (model.state.linear ? "1.6k" : "8") : Self.prompts[row] ?? ""
        let unit = row == .growth && !model.state.linear ? "%" : "$"
        // Empty isn't an error, just incomplete; isInvalid only flags text that can't be a number.
        return NumberField(text: text, row: row, prompt: prompt, invalid: model.state.isInvalid(row),
                           focus: $focus, request: focusRequest)
            .frame(height: 18)
            .padding(.leading, 22)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(width: Style.fieldWidth)
            .background(RoundedRectangle(cornerRadius: Style.fieldRadius).fill(.quaternary))
            .overlay(RoundedRectangle(cornerRadius: Style.fieldRadius).strokeBorder(row == .growth ? dragOutline ?? .clear : .clear, lineWidth: 1))
            // The unit is drawn, not typed, so the text is just the number.
            .overlay(alignment: .leading) {
                Text(unit)
                    .font(.system(size: Style.fieldSize).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .allowsHitTesting(false)
            }
    }

    // MARK: Result

    private func result(_ r: Readout) -> some View {
        let color: Color = switch r.tone {
        case .alive: Style.alive
        case .dead: Style.dead
        case .neutral: .secondary
        }
        // Always two lines (" " holds an empty one open) so the window never changes
        // height as you type.
        return VStack(spacing: 4) {
            Text(r.headline)
                .font(.system(size: Style.verdictSize, weight: .bold))
                .tracking(1)
                .foregroundStyle(color)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity)
                // The chart toggle is a small icon beside the verdict, not a row of its own.
                // Mouse-only like the unit toggles: Tab and Return stay in the boxes.
                .overlay(alignment: .trailing) {
                    if r.tone != .neutral {
                        Button { model.chartShown.toggle() } label: {
                            Image(systemName: "chart.xyaxis.line").font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(model.chartShown ? .secondary : .tertiary)
                        .focusable(false)
                        .help(model.chartShown ? "Hide chart" : "Show chart")
                    }
                }
            Text(r.line1.isEmpty ? " " : r.line1)
        }
        .font(.system(size: Style.detailSize).monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
