import Foundation

/// The four fields exactly as typed.
public struct RawInputs: Equatable, Sendable, Codable {
    public var cash: String
    public var expenses: String
    public var revenue: String
    public var growth: String

    public init(cash: String, expenses: String, revenue: String, growth: String) {
        self.cash = cash
        self.expenses = expenses
        self.revenue = revenue
        self.growth = growth
    }
}

/// An amount field's value if usable: a number, and not negative.
public func amountValue(_ text: String) -> Double? {
    parseAmount(text).flatMap { $0 >= 0 ? $0 : nil }
}

/// The growth field's value if usable: a number, and better than −100%.
public func growthValue(_ text: String) -> Double? {
    parsePercent(text).flatMap { $0 > -1 ? $0 : nil }
}

/// One typed field → its monthly model value, or nil if unusable. $ growth may be negative.
/// `revenueUnit` matters only for $ growth, which adds to the Revenue box's figure.
public func fieldValue(_ row: Row, text: String, unit: Period, linear: Bool, revenueUnit: Period = .month) -> Double? {
    switch row {
    case .cash: amountValue(text)
    case .growth where linear: parseAmount(text).map { linearFromUnit($0, unit, revenue: revenueUnit) }
    case .growth: growthValue(text).map { growthFromUnit($0, unit) }
    case .expenses, .revenue: amountValue(text).map { amountFromUnit($0, unit) }
    }
}

/// A monthly model value → what the field shows in `unit`. Inverse of fieldValue.
/// No "$" or "%": the box draws the unit.
public func fieldText(_ row: Row, monthly: Double, unit: Period, linear: Bool, revenueUnit: Period = .month) -> String {
    switch row {
    case .growth where linear: normalizeField(formatMoney(linearToUnit(monthly, unit, revenue: revenueUnit)))
    case .growth: normalizeField(formatPercent(growthToUnit(monthly, unit)))
    case .cash: normalizeField(formatMoney(monthly))
    case .expenses, .revenue: normalizeField(formatMoney(amountToUnit(monthly, unit)))
    }
}

/// % ↔ $ growth at the same first-period step on the Revenue box's figure, in the growth
/// box's period,
/// so 8%/mo on $20k/mo revenue becomes +$1.6k/mo (8% of 20k), and back.
public func switchGrowthKind(_ monthlyGrowth: Double, toLinear: Bool, monthlyRevenue: Double, unit: Period,
                             revenueUnit: Period = .month) -> Double? {
    let revenue = amountToUnit(monthlyRevenue, revenueUnit)
    guard revenue > 0 else { return nil }
    return toLinear
        ? linearFromUnit(growthToUnit(monthlyGrowth, unit) * revenue, unit, revenue: revenueUnit)
        : growthFromUnit(linearToUnit(monthlyGrowth, unit, revenue: revenueUnit) / revenue, unit)
}

public enum Tone: String, Sendable, Codable {
    case alive, dead, neutral
}

/// The "alive if" column. Empty strings when there's no projection.
public struct Hints: Equatable, Sendable, Codable {
    public var cash: String
    public var expenses: String
    public var revenue: String
    public var growth: String

    public init(cash: String, expenses: String, revenue: String, growth: String) {
        self.cash = cash
        self.expenses = expenses
        self.revenue = revenue
        self.growth = growth
    }

    public static let none = Hints(cash: "", expenses: "", revenue: "", growth: "")

    public subscript(row: Row) -> String {
        get {
            switch row {
            case .cash: cash
            case .expenses: expenses
            case .revenue: revenue
            case .growth: growth
            }
        }
        set {
            switch row {
            case .cash: cash = newValue
            case .expenses: expenses = newValue
            case .revenue: revenue = newValue
            case .growth: growth = newValue
            }
        }
    }
}

/// Everything below the divider and in the "alive if" column, as plain strings.
/// An empty line is "".
public struct Readout: Equatable, Sendable, Codable {
    public var tone: Tone
    public var headline: String
    public var line1: String
    public var line2: String
    public var hints: Hints

    public init(tone: Tone, headline: String, line1: String, line2: String, hints: Hints) {
        self.tone = tone
        self.headline = headline
        self.line1 = line1
        self.line2 = line2
        self.hints = hints
    }
}

private func hint(_ threshold: Threshold, _ format: (Double) -> String) -> String {
    switch threshold {
    case let .value(v): format(v)
    case .never: "never"
    case .any: "any"
    }
}

/// From monthly model inputs, each empty box standing in as 0 (nil if a typed box can't be
/// read), and the list of empty boxes. With exactly one empty, the line says what that box
/// has to be: each lever's threshold holds the other three fixed, so its own value never
/// enters. Durations always read in months. With `taxes`, the projection runs on after-tax
/// inputs and the hints are turned back into the pre-tax numbers you'd type.
public func readout(_ inputs: Inputs?, empty: [Row], units: Units, taxes: TaxAssumptions? = nil, now: Date) -> Readout {
    func neutral(_ line1: String, _ hints: Hints = .none) -> Readout {
        Readout(tone: .neutral, headline: "—", line1: line1, line2: "", hints: hints)
    }
    guard let inputs else { return neutral("Check the numbers in red") }
    if empty.count > 1 { return neutral("Enter at least three numbers") }
    // With revenue the empty box, taxes are judged at the stand-in 0, so one that only
    // starts above some revenue (Texas's $2.65M) is left out of that answer.
    let taxed = taxes.map { withTaxes(inputs, $0) }
    let b = taxed.map { $0.gross(breakevens($0.inputs)) } ?? breakevens(inputs)
    let hints = Hints(
        cash: hint(b.cash) { "≥ " + formatMoneyBound($0, roundUp: true) },
        expenses: hint(b.expenses) { "≤ " + formatMoneyBound(amountToUnit($0, units.expenses), roundUp: false) },
        revenue: hint(b.revenue) { "≥ " + formatMoneyBound(amountToUnit($0, units.revenue), roundUp: true) },
        growth: hint(b.growth) {
            inputs.linear
                ? "≥ " + formatMoneyBound(linearToUnit($0, units.growth, revenue: units.revenue), roundUp: true)
                : "≥ " + formatPercentBound(growthToUnit($0, units.growth), roundUp: true)
        })

    if let row = empty.first {
        var only = Hints.none
        only[row] = hints[row]
        return neutral(solvedLine(row, b[row], hints[row], units), only)
    }
    guard let p = project(taxed?.inputs ?? inputs) else { return neutral("Check the numbers in red") }

    // One line under the verdict: when, as a duration and a day. (What it costs and what's
    // left are in the "alive if" column and the chart's tooltip.)
    if p.verdict == .alive {
        let T = p.monthsToProfitability ?? 0
        let line1 = T == 0 ? "Already profitable" : "Profitable in \(formatMonths(T)) · \(formatDate(months: T, from: now))"
        return Readout(tone: .alive, headline: "DEFAULT ALIVE", line1: line1, line2: "", hints: hints)
    }
    let runway = p.runwayMonths ?? 0
    return Readout(
        tone: .dead, headline: "DEFAULT DEAD",
        line1: "Out of cash in \(formatMonths(runway)) · \(formatDate(months: runway, from: now))", line2: "", hints: hints)
}

/// "Default alive with revenue ≥ $28.7k / month": the one empty box, solved.
private func solvedLine(_ row: Row, _ threshold: Threshold, _ hint: String, _ units: Units) -> String {
    let noun = switch row {
    case .cash: "cash"
    case .expenses: "expenses"
    case .revenue: "revenue"
    case .growth: "growth"
    }
    switch threshold {
    case .never: return "Not default alive at any \(noun)"
    case .any: return "Default alive at any \(noun)"
    case .value:
        let per = switch row {
        case .cash: ""
        case .expenses: " / \(units.expenses.rawValue)"
        case .revenue: " / \(units.revenue.rawValue)"
        case .growth: " / \(units.growth.rawValue)"
        }
        return "Default alive with \(noun) \(hint)\(per)"
    }
}

/// The same, straight from the typed strings.
public func readout(_ raw: RawInputs, units: Units = .monthly, linear: Bool = false, taxes: TaxAssumptions? = nil, now: Date) -> Readout {
    let texts: [(Row, String, Period)] = [
        (.cash, raw.cash, .month), (.expenses, raw.expenses, units.expenses),
        (.revenue, raw.revenue, units.revenue), (.growth, raw.growth, units.growth),
    ]
    let empty = texts.filter { $0.1.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.0)
    let values = texts.map { empty.contains($0.0) ? 0 : fieldValue($0.0, text: $0.1, unit: $0.2, linear: linear, revenueUnit: units.revenue) }
    guard let c = values[0], let e = values[1], let r = values[2], let g = values[3] else {
        return readout(nil, empty: empty, units: units, taxes: taxes, now: now)
    }
    let inputs = Inputs(cash: c, monthlyExpenses: e, monthlyRevenue: r, monthlyGrowth: g, linear: linear)
    return readout(inputs, empty: empty, units: units, taxes: taxes, now: now)
}
