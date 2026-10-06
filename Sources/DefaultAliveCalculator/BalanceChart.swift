import Charts
import DefaultAliveCore
import SwiftUI

/// Cash balance over time, in months. One series in the verdict color (a status: the
/// headline already says ALIVE/DEAD in words), so no legend; the caption names it. The
/// zero line is a little stronger than the grid because crossing it is the whole question.
/// Same layout as drawChart() in design/index.html.
struct BalanceChart: View {
    let curve: BalanceCurve
    let now: Date
    @State private var hover: BalanceCurve.Point?

    private var color: Color { curve.verdict == .alive ? Style.alive : Style.dead }

    var body: some View {
        let y = yAxis
        VStack(alignment: .leading, spacing: 4) {
            Text("Cash balance").font(.system(size: 11)).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(curve.points.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("Month", p.t), y: .value("Cash", p.balance))
                        .foregroundStyle(color.opacity(0.1))
                    LineMark(x: .value("Month", p.t), y: .value("Cash", p.balance))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.primary.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1))
                if let m = curve.marker {
                    // The dip has clear air under it unless it sits within 18pt of the
                    // plot's floor, where a label below would land on the axis labels.
                    let roomBelow = (m.balance - y.lo) / (y.hi - y.lo) * Style.chartHeight
                    PointMark(x: .value("Month", m.t), y: .value("Cash", m.balance))
                        .symbol { dot }
                        .annotation(position: roomBelow >= 18 ? .bottom : .top, alignment: .center, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if m.kind == .profitable { markerLabel(m) }
                        }
                }
                if let h = hover {
                    RuleMark(x: .value("Month", h.t)).foregroundStyle(Color.primary.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Month", h.t), y: .value("Cash", h.balance))
                        .symbol { dot }
                        .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            tooltip(h)
                        }
                }
            }
            .chartXScale(domain: 0...curve.horizon)
            .chartYScale(domain: y.lo...y.hi)
            .chartXAxis {
                AxisMarks(values: xTicks) { value in
                    let v = value.as(Double.self) ?? 0
                    let last = v == xTicks.last
                    // The last label carries " mo" and often sits near the right edge, where
                    // a centered label got truncated to "1…"; hang it leftward instead.
                    AxisValueLabel(anchor: last && curve.horizon - v < curve.horizon * 0.1 ? .topTrailing : .top) {
                        Text(last ? "\(Self.number(v)) mo" : Self.number(v))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: y.ticks) { value in
                    // Explicit grays: in Charts, .secondary/.quaternary resolve against the accent color
                    // and drew blue gridlines.
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.primary.opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(formatMoney(v)) }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard case let .active(location) = phase, let frame = proxy.plotFrame,
                                  let t: Double = proxy.value(atX: location.x - geo[frame].origin.x)
                            else { hover = nil; return }
                            hover = curve.points.min { abs($0.t - t) < abs($1.t - t) }
                        }
                }
            }
            // Out of cash ends a falling line, which always leaves the top-right corner of
            // the plot empty; next to the marker the label would sit on the line.
            .overlay(alignment: .topTrailing) {
                if let m = curve.marker, m.kind == .broke, hover == nil { markerLabel(m) }
            }
            .font(.system(size: 10).monospacedDigit())
            .frame(height: Style.chartHeight + 18)
            // The top tick label sits centered on the top gridline, so it needs headroom
            // under the caption.
            .padding(.top, 6)
        }
    }

    /// Filled dot with a ring in the window color, so it stays legible on the line.
    private var dot: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
    }

    private func markerLabel(_ m: BalanceCurve.Marker) -> some View {
        Text("\(m.kind == .profitable ? "Profitable" : "Out of cash") · \(formatMonthYear(months: m.t, from: now))")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    private func tooltip(_ p: BalanceCurve.Point) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(formatMoney(p.balance)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
            Text("\(formatMonthYear(months: p.t, from: now)) · \(formatMonths(p.t))")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)).shadow(radius: 4, y: 2))
    }

    // MARK: Axes (same nice-step rule as the mock)

    private static func niceStep(_ range: Double, _ count: Double) -> Double {
        let raw = range / count
        let mag = pow(10, floor(log10(raw)))
        let n = raw / mag
        return mag * (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10)
    }

    private static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }

    private var xTicks: [Double] {
        let step = Self.niceStep(curve.horizon, 4)
        return stride(from: 0, through: curve.horizon + 1e-9, by: step).map { $0 }
    }

    private var yAxis: (lo: Double, hi: Double, ticks: [Double]) {
        let balances = curve.points.map(\.balance)
        let lo0 = min(0, balances.min() ?? 0), hi0 = max(balances.max() ?? 1, 1)
        let step = Self.niceStep(hi0 - lo0, 3)
        let lo = (lo0 / step).rounded(.down) * step, hi = (hi0 / step).rounded(.up) * step
        return (lo, hi, Array(stride(from: lo, through: hi + step / 2, by: step)))
    }
}
