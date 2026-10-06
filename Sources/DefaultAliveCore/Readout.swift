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
public func fieldValue(_ row: Row, text: String, unit: Period, linear: Bool) -> Double? {
    switch row {
    case .cash: amountValue(text)
    case .growth where linear: parseAmount(text).map { linearFromUnit($0, unit) }
    case .growth: growthValue(text).map { growthFromUnit($0, unit) }
    case .expenses, .revenue: amountValue(text).map { amountFromUnit($0, unit) }
    }
}

/// A monthly model value → what the field shows in `unit`. Inverse of fieldValue.
/// $ growth keeps its "$" so it can't be mistaken for a percentage.
public func fieldText(_ row: Row, monthly: Double, unit: Period, linear: Bool) -> String {
    switch row {
    case .growth where linear: formatMoney(linearToUnit(monthly, unit))
    case .growth: formatPercent(growthToUnit(monthly, unit))
    case .cash: formatMoney(monthly).replacingOccurrences(of: "$", with: "")
    case .expenses, .revenue: formatMoney(amountToUnit(monthly, unit)).replacingOccurrences(of: "$", with: "")
    }
}

/// % ↔ $ growth at the same first-period step, measured in the growth field's own unit,
/// so 8%/mo on $20k/mo revenue becomes +$1.6k/mo (8% of 20k), and back.
public func switchGrowthKind(_ monthlyGrowth: Double, toLinear: Bool, monthlyRevenue: Double, unit: Period) -> Double? {
    let revenue = amountToUnit(monthlyRevenue, unit)
    guard revenue > 0 else { return nil }
    return toLinear
        ? linearFromUnit(growthToUnit(monthlyGrowth, unit) * revenue, unit)
        : growthFromUnit(linearToUnit(monthlyGrowth, unit) / revenue, unit)
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
        switch row {
        case .cash: cash
        case .expenses: expenses
        case .revenue: revenue
        case .growth: growth
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

/// From monthly model inputs (nil if a field is unusable). Durations always read in months.
public func readout(_ inputs: Inputs?, filledIn: Bool, units: Units, now: Date) -> Readout {
    guard let inputs, let p = project(inputs) else {
        return Readout(
            tone: .neutral, headline: "—",
            line1: filledIn ? "Check the numbers in red" : "Enter all four numbers", line2: "", hints: .none)
    }

    let b = breakevens(inputs)
    let hints = Hints(
        cash: hint(b.cash) { "≥ " + formatMoneyBound($0, roundUp: true) },
        expenses: hint(b.expenses) { "≤ " + formatMoneyBound(amountToUnit($0, units.expenses), roundUp: false) },
        revenue: hint(b.revenue) { "≥ " + formatMoneyBound(amountToUnit($0, units.revenue), roundUp: true) },
        growth: hint(b.growth) {
            inputs.linear
                ? "≥ " + formatMoneyBound(linearToUnit($0, units.growth), roundUp: true)
                : "≥ " + formatPercentBound(growthToUnit($0, units.growth), roundUp: true)
        })

    if p.verdict == .alive {
        let T = p.monthsToProfitability ?? 0
        if T == 0 {
            return Readout(tone: .alive, headline: "DEFAULT ALIVE", line1: "Already profitable", line2: "Revenue covers expenses", hints: hints)
        }
        return Readout(
            tone: .alive, headline: "DEFAULT ALIVE",
            line1: "Profitable in \(formatMonths(T)) · \(formatMonthYear(months: T, from: now))",
            line2: "Needs \(formatMoney(p.capitalNeeded ?? 0)) · \(formatMoney(p.cushion ?? 0)) to spare",
            hints: hints)
    }

    let runway = p.runwayMonths ?? 0
    let line1 = runway == 0
        ? "Out of cash now"
        : "Out of cash in \(formatMonths(runway)) · \(formatMonthYear(months: runway, from: now))"
    let line2 = if let needed = p.capitalNeeded, let cushion = p.cushion {
        "Needs \(formatMoney(needed)) · \(formatMoney(-cushion)) short"
    } else {
        "Never profitable at this growth"
    }
    return Readout(tone: .dead, headline: "DEFAULT DEAD", line1: line1, line2: line2, hints: hints)
}

/// The same, straight from the typed strings.
public func readout(_ raw: RawInputs, units: Units = .monthly, linear: Bool = false, now: Date) -> Readout {
    let texts: [(Row, String, Period)] = [
        (.cash, raw.cash, .month), (.expenses, raw.expenses, units.expenses),
        (.revenue, raw.revenue, units.revenue), (.growth, raw.growth, units.growth),
    ]
    let values = texts.map { fieldValue($0.0, text: $0.1, unit: $0.2, linear: linear) }
    let filledIn = texts.allSatisfy { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }
    guard let c = values[0], let e = values[1], let r = values[2], let g = values[3] else {
        return readout(nil, filledIn: filledIn, units: units, now: now)
    }
    let inputs = Inputs(cash: c, monthlyExpenses: e, monthlyRevenue: r, monthlyGrowth: g, linear: linear)
    return readout(inputs, filledIn: filledIn, units: units, now: now)
}
