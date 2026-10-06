import Foundation

// For each input: the value that makes capital needed exactly equal cash, holding the
// other three fixed. Capital needed is monotone in every input (up in expenses, down in
// cash/revenue/growth), so each has one crossing. Monthly units.

/// A single-lever breakeven: the value one input would need, the others unchanged.
public enum Threshold: Equatable, Sendable {
    case value(Double)
    /// No value of this input makes the company default alive.
    case never
    /// Every value does.
    case any
}

public struct Breakevens: Equatable, Sendable {
    public var cash: Threshold
    public var expenses: Threshold
    public var revenue: Threshold
    public var growth: Threshold

    public subscript(row: Row) -> Threshold {
        switch row {
        case .cash: cash
        case .expenses: expenses
        case .revenue: revenue
        case .growth: growth
        }
    }
}

public func breakevens(_ inputs: Inputs) -> Breakevens {
    let cash = inputs.cash
    let E = inputs.monthlyExpenses
    let R = inputs.monthlyRevenue
    let g = inputs.monthlyGrowth

    if inputs.linear {
        // √(2a·cash) is the revenue gap that cash can carry all the way to profitability.
        let reach = g > 0 ? (2 * g * cash).squareRoot() : 0
        return Breakevens(
            cash: R >= E ? .value(0) : g > 0 ? .value((E - R) * (E - R) / (2 * g)) : .never,
            expenses: .value(R + reach),
            revenue: E - reach <= 0 ? .any : .value(E - reach),
            growth: R >= E ? .any : cash == 0 ? .never : .value((E - R) * (E - R) / (2 * cash)))
    }

    let r = log1p(g)
    let C = compoundingCapital(E, R, r)

    var maxExpenses = R
    if R > 0, r > 0 {
        var hi = max(E, R) * 2
        for _ in 0..<100 where compoundingCapital(hi, R, r) <= cash { hi *= 2 }
        maxExpenses = bisect({ compoundingCapital($0, R, r) }, cash, R, hi)
    }

    // Searched in log space, since the answer can sit many orders below E.
    var minRevenue = E
    if r > 0, E > 0 {
        minRevenue = exp(bisect({ compoundingCapital(E, exp($0), r) }, cash, log(E) - 40, log(E)))
    }

    // None needed if already profitable; none suffices from zero revenue or zero cash.
    let minGrowth: Threshold
    if R >= E {
        minGrowth = .any
    } else if R == 0 || cash == 0 {
        minGrowth = .never
    } else {
        var hi = 0.01
        for _ in 0..<100 where compoundingCapital(E, R, log1p(hi)) > cash { hi *= 2 }
        minGrowth = .value(bisect({ compoundingCapital(E, R, log1p($0)) }, cash, 0, hi))
    }

    return Breakevens(
        cash: C.isFinite ? .value(C) : .never,
        expenses: .value(maxExpenses),
        revenue: .value(minRevenue),
        growth: minGrowth)
}

private func compoundingCapital(_ E: Double, _ R: Double, _ r: Double) -> Double {
    if R >= E { return 0 }
    guard R > 0, r > 0 else { return .infinity }
    return E * (log(E / R) / r) - (E - R) / r
}

/// x where f(x) crosses target, given f(lo) and f(hi) straddle it.
private func bisect(_ f: (Double) -> Double, _ target: Double, _ low: Double, _ high: Double) -> Double {
    let up = f(high) > f(low)
    var lo = low, hi = high
    for _ in 0..<200 {
        let mid = (lo + hi) / 2
        if mid <= lo || mid >= hi { break }
        if (f(mid) < target) == up { lo = mid } else { hi = mid }
    }
    return (lo + hi) / 2
}
