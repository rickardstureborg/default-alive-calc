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

public enum Tone: String, Sendable, Codable {
    case alive, dead, neutral
}

/// Everything below the divider, as plain strings. An empty line is "".
public struct Readout: Equatable, Sendable, Codable {
    public var tone: Tone
    public var headline: String
    public var line1: String
    public var line2: String

    public init(tone: Tone, headline: String, line1: String, line2: String) {
        self.tone = tone
        self.headline = headline
        self.line1 = line1
        self.line2 = line2
    }
}

public func readout(_ raw: RawInputs, now: Date) -> Readout {
    guard let cash = amountValue(raw.cash),
          let expenses = amountValue(raw.expenses),
          let revenue = amountValue(raw.revenue),
          let growth = growthValue(raw.growth),
          let p = project(Inputs(cash: cash, monthlyExpenses: expenses, monthlyRevenue: revenue, monthlyGrowth: growth))
    else {
        let filledIn = ![raw.cash, raw.expenses, raw.revenue, raw.growth].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Readout(tone: .neutral, headline: "—", line1: filledIn ? "Check the numbers in red" : "Enter all four numbers", line2: "")
    }

    if p.verdict == .alive {
        let T = p.monthsToProfitability ?? 0
        if T == 0 {
            return Readout(tone: .alive, headline: "DEFAULT ALIVE", line1: "Already profitable", line2: "Revenue covers expenses")
        }
        return Readout(
            tone: .alive, headline: "DEFAULT ALIVE",
            line1: "Profitable in \(formatMonths(T)) · \(formatMonthYear(months: T, from: now))",
            line2: "Needs \(formatMoney(p.capitalNeeded ?? 0)) · \(formatMoney(p.cushion ?? 0)) to spare")
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
    return Readout(tone: .dead, headline: "DEFAULT DEAD", line1: line1, line2: line2)
}
