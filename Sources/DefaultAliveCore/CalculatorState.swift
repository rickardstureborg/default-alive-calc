import Foundation

public enum Row: CaseIterable, Sendable {
    case cash, expenses, revenue, growth

    /// Up / Down arrows: the box above or below, staying put at the ends.
    public func stepped(down: Bool) -> Row {
        let all = Row.allCases
        let i = all.firstIndex(of: self)! + (down ? 1 : -1)
        return all.indices.contains(i) ? all[i] : self
    }

    /// Tab / Return order, wrapping at both ends.
    public func moved(forward: Bool) -> Row {
        let all = Row.allCases
        let i = all.firstIndex(of: self)!
        return all[(i + (forward ? 1 : all.count - 1)) % all.count]
    }
}

/// One input box.
public struct Field: Equatable, Sendable {
    public var text: String
    public var unit: Period
    /// What was actually typed, kept until the next edit so cycling the unit back
    /// restores the exact string.
    var origin: Origin?
    /// The precise monthly value while the box shows a converted (rounded) display, so the
    /// math never sees the rounding.
    var exact: Double?

    struct Origin: Equatable, Sendable {
        var text: String
        var unit: Period
    }

    public init(text: String = "", unit: Period = .month) {
        self.text = text
        self.unit = unit
    }
}

/// Everything the form edits. Growth has two boxes, one per kind, so flipping % ↔ $ shows
/// each one's own input and never discards the other; a conversion only fills a box that's
/// empty. Pure value type so the form's behavior is unit-tested here, not in the view.
public struct CalculatorState: Equatable, Sendable {
    public var cash = Field()
    public var expenses = Field()
    public var revenue = Field()
    public var growthPercent = Field()
    public var growthDollar = Field()
    public var linear = false
    public var taxesOn = false
    /// Percent of revenue sourced to Oakland / Washington, as typed.
    public var oaklandShare = "100"
    public var washingtonShare = "10"

    /// nil when taxes are off or a share isn't a number.
    public var taxAssumptions: TaxAssumptions? {
        guard taxesOn, let oakland = parsePercent(oaklandShare), let washington = parsePercent(washingtonShare) else { return nil }
        return TaxAssumptions(oaklandShare: oakland, washingtonShare: washington)
    }

    /// The size of the tax effect for the checkbox line, "≈ 0.36% + $450/yr"; "" when off.
    public var taxSummary: String {
        guard let taxed = taxed else { return "" }
        return "≈ \(formatPercent(taxed.revenueRate)) + $\(Int((taxed.fixedMonthly * 12).rounded()))/yr"
    }

    private var taxed: Taxed? {
        guard let inputs, let a = taxAssumptions else { return nil }
        return withTaxes(inputs, a)
    }

    /// What the chart plots: after-tax when taxes are on.
    public var chartInputs: Inputs? { taxed?.inputs ?? inputs }

    public init() {}

    /// A preset: `input.growth` goes to whichever kind `linear` says.
    public init(input: RawInputs, units: Units = .monthly, linear: Bool = false, taxes: TaxAssumptions? = nil) {
        cash.text = normalizeField(input.cash)
        expenses = Field(text: normalizeField(input.expenses), unit: units.expenses)
        revenue = Field(text: normalizeField(input.revenue), unit: units.revenue)
        growthPercent.unit = units.growth
        growthDollar.unit = units.growth
        self.linear = linear
        self[.growth].text = normalizeField(input.growth)
        if let taxes {
            taxesOn = true
            oaklandShare = trimZeros(String(format: "%.4f", taxes.oaklandShare * 100))
            washingtonShare = trimZeros(String(format: "%.4f", taxes.washingtonShare * 100))
        }
    }

    private subscript(row: Row) -> Field {
        get {
            switch row {
            case .cash: cash
            case .expenses: expenses
            case .revenue: revenue
            case .growth: linear ? growthDollar : growthPercent
            }
        }
        set {
            switch row {
            case .cash: cash = newValue
            case .expenses: expenses = newValue
            case .revenue: revenue = newValue
            case .growth: if linear { growthDollar = newValue } else { growthPercent = newValue }
            }
        }
    }

    public func field(_ row: Row) -> Field { self[row] }

    public var units: Units {
        Units(expenses: expenses.unit, revenue: revenue.unit, growth: self[.growth].unit)
    }

    private func monthly(_ row: Row) -> Double? {
        let f = self[row]
        return f.exact ?? fieldValue(row, text: f.text, unit: f.unit, linear: linear)
    }

    public mutating func edit(_ row: Row, text: String) {
        // Live: regroup thousands and drop "$"/"%" on every keystroke (see normalizeField).
        self[row] = Field(text: normalizeField(text), unit: self[row].unit)
    }

    public mutating func cycleUnit(_ row: Row) {
        var f = self[row]
        if f.origin == nil {
            guard let v = monthly(row) else {
                f.unit = f.unit.next
                self[row] = f
                return
            }
            f.origin = .init(text: f.text, unit: f.unit)
            f.exact = v
        }
        f.unit = f.unit.next
        if let origin = f.origin, origin.unit == f.unit {
            f = Field(text: origin.text, unit: origin.unit)
        } else if let exact = f.exact {
            f.text = fieldText(row, monthly: exact, unit: f.unit, linear: linear)
        }
        self[row] = f
    }

    public mutating func toggleGrowthKind() {
        let from = self[.growth]
        let seed = monthly(.growth)
        let revenue = monthly(.revenue)
        linear.toggle()
        // Convenience only: seed an empty box from the other kind, in the same period.
        guard self[.growth].text.trimmingCharacters(in: .whitespaces).isEmpty,
              let seed, let revenue,
              let v = switchGrowthKind(seed, toLinear: linear, monthlyRevenue: revenue, unit: from.unit)
        else { return }
        var to = Field(text: fieldText(.growth, monthly: v, unit: from.unit, linear: linear), unit: from.unit)
        to.exact = v
        self[.growth] = to
    }

    /// Growth set from the chart: the box shows it in its own unit and kind, and the math
    /// keeps the exact value (no rounding through the display).
    public mutating func setGrowth(monthly: Double) {
        let unit = self[.growth].unit
        var field = Field(text: fieldText(.growth, monthly: monthly, unit: unit, linear: linear), unit: unit)
        field.exact = monthly
        self[.growth] = field
    }

    /// Return: rewrite an expression in the box to its result. Tab doesn't, so "163+5"
    /// stays visible until you say you're done with it.
    public mutating func commit(_ row: Row) {
        if let compact = compactField(row, text: self[row].text, linear: linear) {
            edit(row, text: compact)
        }
    }

    public mutating func clear() {
        for keyPath in [\Self.cash, \.expenses, \.revenue, \.growthPercent, \.growthDollar] {
            self[keyPath: keyPath] = Field(unit: self[keyPath: keyPath].unit)
        }
    }

    /// Red text: something's typed and it can't be a number of the right kind.
    public func isInvalid(_ row: Row) -> Bool {
        let text = self[row].text
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return switch row {
        case .growth where linear: parseAmount(text) == nil
        case .growth: growthValue(text) == nil
        case .cash, .expenses, .revenue: amountValue(text) == nil
        }
    }

    public var inputs: Inputs? {
        guard let c = monthly(.cash), let e = monthly(.expenses), let r = monthly(.revenue), let g = monthly(.growth) else {
            return nil
        }
        return Inputs(cash: c, monthlyExpenses: e, monthlyRevenue: r, monthlyGrowth: g, linear: linear)
    }

    public func readout(now: Date) -> Readout {
        let filledIn = Row.allCases.allSatisfy { !self[$0].text.trimmingCharacters(in: .whitespaces).isEmpty }
        return DefaultAliveCore.readout(inputs, filledIn: filledIn, units: units, taxes: taxAssumptions, now: now)
    }
}
