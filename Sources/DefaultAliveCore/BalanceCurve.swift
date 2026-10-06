import Foundation

/// Cash balance over time, for the chart. Months throughout.
public struct BalanceCurve: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var t: Double
        public var balance: Double
    }

    public enum MarkerKind: Equatable, Sendable { case profitable, broke }

    public struct Marker: Equatable, Sendable {
        public var t: Double
        public var balance: Double
        public var kind: MarkerKind
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
