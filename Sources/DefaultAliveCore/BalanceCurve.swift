import Foundation

/// Cash balance over time, for the chart. Months throughout.
public struct BalanceCurve: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var t: Double
        public var balance: Double

        public init(t: Double, balance: Double) {
            self.t = t
            self.balance = balance
        }
    }

    public enum MarkerKind: Equatable, Sendable { case profitable, broke }

    public struct Marker: Equatable, Sendable {
        public var t: Double
        public var balance: Double
        public var kind: MarkerKind

        public init(t: Double, balance: Double, kind: MarkerKind) {
            self.t = t
            self.balance = balance
            self.kind = kind
        }
    }

    public var points: [Point]
    public var horizon: Double
    public var marker: Marker?
    public var verdict: Verdict
}

/// Bank balance from now until the story is told: past profitability when alive, to zero
/// when dead.
public func balanceCurve(_ inputs: Inputs, samples: Int = 160) -> BalanceCurve? {
    guard let p = project(inputs) else { return nil }
    let horizon: Double
    var marker: BalanceCurve.Marker?
    if p.verdict == .alive, let T = p.monthsToProfitability, T > 0 {
        // Far enough past the low point to show the recovery, not so far that the
        // exponential climb flattens the dip.
        horizon = T * 1.35
        marker = .init(t: T, balance: p.cushion ?? 0, kind: .profitable)
    } else if p.verdict == .alive {
        horizon = 24
    } else {
        let runway = p.runwayMonths ?? 0
        horizon = max(runway * 1.15, 1)
        marker = .init(t: runway, balance: 0, kind: .broke)
    }
    let end = p.verdict == .dead ? (p.runwayMonths ?? 0) : horizon
    let points = (0...samples).map { i in
        let t = end * Double(i) / Double(samples)
        return BalanceCurve.Point(t: t, balance: inputs.cash - cumulativeBurn(inputs, months: t))
    }
    return BalanceCurve(points: points, horizon: horizon, marker: marker, verdict: p.verdict)
}

/// Where dragging the profitability dot lands.
public struct ProfitDrag: Equatable, Sendable {
    public var monthlyGrowth: Double
    public var monthsToProfitability: Double
    public var balance: Double
    /// Held at the zero line: the growth there is the default-alive minimum.
    public var pinned: Bool
}

/// Dragging the profitability dot changes growth, the one thing the dot's position can say:
/// expenses, revenue and cash stay put. As growth varies, the dot (T, cash − C) moves along a
/// straight line, because capital needed is proportional to T: C = k·T with
/// k = E − (E−R)/ln(E/R) for compounding growth (since ln(1+g) = ln(E/R)/T) and k = (E−R)/2
/// for linear. So the drag projects the pointer onto that line, in screen space (the axes'
/// scales decide what "nearest" means), then reads growth off T.
///
/// It stops at the zero line, where growth is exactly the default-alive minimum: past it the
/// company is dead, the profitability dot vanishes from the chart, and there'd be nothing
/// left to drag back. It also stops at half a month (growth runs away below that) and at
/// `maxMonths`, the visible edge.
public func dragProfitPoint(to t: Double, balance: Double, inputs: Inputs, pointsPerMonth px: Double,
                            pointsPerDollar py: Double, maxMonths: Double = .infinity) -> ProfitDrag? {
    let E = inputs.monthlyExpenses, R = inputs.monthlyRevenue, cash = inputs.cash
    guard E > R, inputs.linear || R > 0 else { return nil }
    let k = inputs.linear ? (E - R) / 2 : E - (E - R) / log(E / R)
    guard k > 0 else { return nil }
    // Minimize (px·(T − t))² + (py·(cash − k·T − balance))² over T.
    let nearest = (px * px * t + k * py * py * (cash - balance)) / (px * px + k * k * py * py)
    let zeroLine = cash / k
    let T = min(max(nearest, 0.5), maxMonths, zeroLine)
    let growth = inputs.linear ? (E - R) / T : expm1(log(E / R) / T)
    return ProfitDrag(monthlyGrowth: growth, monthsToProfitability: T, balance: cash - k * T, pinned: T == zeroLine)
}

/// Monthly revenue `t` months from now. Shrinking linear revenue stops at zero.
public func revenueAt(_ inputs: Inputs, months t: Double) -> Double {
    inputs.linear
        ? max(0, inputs.monthlyRevenue + inputs.monthlyGrowth * t)
        : inputs.monthlyRevenue * exp(log1p(inputs.monthlyGrowth) * t)
}
