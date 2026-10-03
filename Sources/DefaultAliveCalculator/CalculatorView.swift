import DefaultAliveCore
import SwiftUI

/// Layout tokens. design/index.html defines the same names as CSS variables
/// (--width, --padding, …), so a design approved in the browser ports by copying numbers.
enum Style {
    static let width: CGFloat = 320
    static let padding: CGFloat = 20
    static let rowSpacing: CGFloat = 10
    static let labelSize: CGFloat = 13
    static let fieldSize: CGFloat = 15
    static let fieldWidth: CGFloat = 120
    static let fieldRadius: CGFloat = 6
    static let dividerSpacing: CGFloat = 16
    static let verdictSize: CGFloat = 22
    static let detailSize: CGFloat = 12
    static let alive = Color.green
    static let dead = Color.red
}

private enum Field: CaseIterable {
    case cash, expenses, revenue, growth
}

struct CalculatorView: View {
    // The four raw strings are the app's only persisted state, written on every edit.
    @AppStorage("cash") private var cash = ""
    @AppStorage("expenses") private var expenses = ""
    @AppStorage("revenue") private var revenue = ""
    @AppStorage("growth") private var growth = ""

    var body: some View {
        CalculatorForm(cash: $cash, expenses: $expenses, revenue: $revenue, growth: $growth)
    }
}

/// Kept free of storage so --snapshot can render any state without touching saved input.
struct CalculatorForm: View {
    @Binding var cash: String
    @Binding var expenses: String
    @Binding var revenue: String
    @Binding var growth: String
    @FocusState private var focus: Field?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Style.rowSpacing) {
                row("Cash in bank", $cash, prompt: "$1.2M", field: .cash, valid: amountValue(cash) != nil)
                row("Monthly expenses", $expenses, prompt: "80k", field: .expenses, valid: amountValue(expenses) != nil)
                row("Monthly revenue", $revenue, prompt: "20k", field: .revenue, valid: amountValue(revenue) != nil)
                row("Monthly growth", $growth, prompt: "8%", field: .growth, valid: growthValue(growth) != nil)
            }
            Divider().padding(.vertical, Style.dividerSpacing)
            result
        }
        .padding(Style.padding)
        .frame(width: Style.width)
        .onAppear { focus = .cash }
        .onReceive(NotificationCenter.default.publisher(for: .clearInputs)) { _ in
            cash = ""
            expenses = ""
            revenue = ""
            growth = ""
            focus = .cash
        }
    }

    private func row(_ label: String, _ text: Binding<String>, prompt: String, field: Field, valid: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: Style.labelSize))
            Spacer()
            TextField(label, text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: Style.fieldSize).monospacedDigit())
                // Empty isn't an error, just incomplete; only flag text that can't be a number.
                .foregroundStyle(valid || text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty ? Color.primary : Style.dead)
                .focused($focus, equals: field)
                .onSubmit { focus = next(after: field) }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(width: Style.fieldWidth)
                .background(RoundedRectangle(cornerRadius: Style.fieldRadius).fill(.quaternary))
        }
    }

    private func next(after field: Field) -> Field? {
        let all = Field.allCases
        return all.firstIndex(of: field).flatMap { $0 + 1 < all.count ? all[$0 + 1] : nil }
    }

    private var result: some View {
        let r = readout(RawInputs(cash: cash, expenses: expenses, revenue: revenue, growth: growth), now: .now)
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
