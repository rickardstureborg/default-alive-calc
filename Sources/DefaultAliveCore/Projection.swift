import Foundation

/// Everything is per month. Compounding growth is a fraction (0.08 = 8%/mo); linear
/// growth is dollars of monthly revenue added each month (5000 = +$5k MRR a month).
public struct Inputs: Equatable, Sendable {
    public var cash: Double
    public var monthlyExpenses: Double
    public var monthlyRevenue: Double
    public var monthlyGrowth: Double
    public var linear: Bool

    public init(cash: Double, monthlyExpenses: Double, monthlyRevenue: Double, monthlyGrowth: Double, linear: Bool = false) {
        self.cash = cash
        self.monthlyExpenses = monthlyExpenses
        self.monthlyRevenue = monthlyRevenue
        self.monthlyGrowth = monthlyGrowth
        self.linear = linear
    }
}

public enum Verdict: Equatable, Sendable {
    case alive, dead
}

public struct Projection: Equatable, Sendable {
    public var verdict: Verdict
    /// Months until revenue covers expenses; nil when that never happens.
    public var monthsToProfitability: Double?
    /// Total burn until profitability; nil when never profitable.
    public var capitalNeeded: Double?
    /// cash − capitalNeeded: to spare when positive, short when negative; nil when never profitable.
    public var cushion: Double?
    /// Months until the bank hits zero; nil when alive.
    public var runwayMonths: Double?
}

// Compounding is growth.tlb.org's calc() with expense growth pinned to 0 (PG: "assuming
// expenses remain constant"): revenue compounds continuously, R·e^(rt) with r = ln(1+g),
// so the answer doesn't depend on whether you think in weeks or months. TLB stops at
// "capital needed"; PG's question adds the comparison against cash in the bank.
// Linear is the alternative for "we add $X of MRR a month": revenue R + a·t.

/// Cumulative cash burned after `t` months.
public func cumulativeBurn(_ inputs: Inputs, months t: Double) -> Double {
    inputs.linear ? linearBurn(inputs, months: t) : compoundingBurn(inputs, months: t)
}

/// PG's test: holding expenses flat and revenue growing at its current rate,
/// does the cash in the bank last until profitability? nil for invalid inputs.
public func project(_ inputs: Inputs) -> Projection? {
    inputs.linear ? projectLinear(inputs) : projectCompounding(inputs)
}

private func compoundingBurn(_ inputs: Inputs, months t: Double) -> Double {
    let r = log1p(inputs.monthlyGrowth)
    let revenueSoFar = r == 0
        ? inputs.monthlyRevenue * t
        : inputs.monthlyRevenue * expm1(r * t) / r
    return inputs.monthlyExpenses * t - revenueSoFar
}

private func projectCompounding(_ inputs: Inputs) -> Projection? {
    let cash = inputs.cash
    let E = inputs.monthlyExpenses
    let R = inputs.monthlyRevenue
    let g = inputs.monthlyGrowth
    guard [cash, E, R, g].allSatisfy(\.isFinite), cash >= 0, E >= 0, R >= 0, g > -1 else {
        return nil
    }

    if R >= E {
        return Projection(verdict: .alive, monthsToProfitability: 0, capitalNeeded: 0, cushion: cash, runwayMonths: nil)
    }

    let r = log1p(g)
    guard R > 0, r > 0 else {
        // Revenue is flat, shrinking, or zero (exponential growth from zero stays zero),
        // so burn never stops. Its rate sits between E−R and E, which brackets the runway.
        let runway = (R == 0 || r == 0)
            ? cash / (E - R)
            : monthsUntilBurned(cash, inputs, between: cash / E, and: cash / (E - R))
        return Projection(verdict: .dead, monthsToProfitability: nil, capitalNeeded: nil, cushion: nil, runwayMonths: runway)
    }

    let T = log(E / R) / r
    // Burn integrated to T: the bank balance bottoms out here, so this is the whole bill.
    let C = E * T - (E - R) / r
    if C <= cash {
        return Projection(verdict: .alive, monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: nil)
    }
    // Burn rate never exceeds E, so cash/E is a lower bound; burn(T) = C > cash is above.
    let runway = monthsUntilBurned(cash, inputs, between: cash / E, and: T)
    return Projection(verdict: .dead, monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: runway)
}

/// Bisection for burn(t) = target. Valid because burn is increasing on [0, T]: there's
/// no closed form once t sits both inside and outside the exponential.
private func monthsUntilBurned(_ target: Double, _ inputs: Inputs, between low: Double, and high: Double) -> Double {
    guard target > 0 else { return 0 }
    var lo = low, hi = high
    for _ in 0..<200 {
        let mid = (lo + hi) / 2
        if mid <= lo || mid >= hi { break }
        if compoundingBurn(inputs, months: mid) < target { lo = mid } else { hi = mid }
    }
    return (lo + hi) / 2
}

// Linear has closed forms throughout: T = (E−R)/a, capital needed C = (E−R)²/(2a).

private func linearBurn(_ inputs: Inputs, months t: Double) -> Double {
    let E = inputs.monthlyExpenses, R = inputs.monthlyRevenue, a = inputs.monthlyGrowth
    // Shrinking revenue stops at zero; after that the whole expense line burns.
    let t0 = a < 0 ? R / -a : .infinity
    let s = min(t, t0)
    return (E - R) * s - a * s * s / 2 + E * max(0, t - t0)
}

private func projectLinear(_ inputs: Inputs) -> Projection? {
    let cash = inputs.cash
    let E = inputs.monthlyExpenses
    let R = inputs.monthlyRevenue
    let a = inputs.monthlyGrowth
    guard [cash, E, R, a].allSatisfy(\.isFinite), cash >= 0, E >= 0, R >= 0 else { return nil }

    if R >= E {
        return Projection(verdict: .alive, monthsToProfitability: 0, capitalNeeded: 0, cushion: cash, runwayMonths: nil)
    }
    // Smaller root of (a/2)t² − (E−R)t + cash = 0, written so it stays exact as a → 0
    // (the textbook form cancels catastrophically there).
    var runway = 2 * cash / ((E - R) + ((E - R) * (E - R) - 2 * a * cash).squareRoot())
    if a > 0 {
        let T = (E - R) / a
        let C = (E - R) * (E - R) / (2 * a)
        if C <= cash {
            return Projection(verdict: .alive, monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: nil)
        }
        return Projection(verdict: .dead, monthsToProfitability: T, capitalNeeded: C, cushion: cash - C, runwayMonths: runway)
    }
    let t0 = a < 0 ? R / -a : .infinity
    if runway > t0 { runway = t0 + (cash - linearBurn(inputs, months: t0)) / E }
    return Projection(verdict: .dead, monthsToProfitability: nil, capitalNeeded: nil, cushion: nil, runwayMonths: runway)
}
