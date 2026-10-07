import Charts
import DefaultAliveCore
import SwiftUI

/// Cash balance over time, in months. One series in the verdict color (a status: the
/// headline already says ALIVE/DEAD in words), so no legend; the caption names it. The
/// zero line is a little stronger than the grid because crossing it is the whole question.
/// Same layout as drawChart() in design/index.html.
///
/// The profitability dot can be dragged to set growth (dragProfitPoint does the math). While
/// it's dragged the axes hold still, so the plot doesn't rescale under the pointer, except
/// that the time axis widens as the dot nears its right edge: otherwise the zero line, the
/// default-alive limit, could sit out of reach.
struct BalanceChart: View {
    let curve: BalanceCurve
    /// What the chart plots: after taxes, if they're ticked.
    let inputs: Inputs
    let revenueUnit: Period
    let now: Date
    /// Each drag position, then nil when the drag ends.
    var onDrag: (ProfitDrag?) -> Void = { _ in }

    @State private var hover: BalanceCurve.Point?
    @State private var frozen: Domain?

    private struct Domain: Equatable {
        var horizon: Double
        var lo: Double
        var hi: Double
    }

    private var color: Color { curve.verdict == .alive ? Style.alive : Style.dead }

    /// While dragging: the curve across the frozen axes and the dot where the new growth
    /// puts profitability. Otherwise: the curve as projected.
    private var shown: (points: [BalanceCurve.Point], marker: BalanceCurve.Marker?, horizon: Double) {
        guard let frozen else { return (curve.points, curve.marker, curve.horizon) }
        let points = (0...160).map { i in
            let t = frozen.horizon * Double(i) / 160
            return BalanceCurve.Point(t: t, balance: inputs.cash - cumulativeBurn(inputs, months: t))
        }
        let p = project(inputs)
        let marker = (p?.monthsToProfitability ?? 0) > 0
            ? BalanceCurve.Marker(t: p!.monthsToProfitability!, balance: p!.cushion ?? 0, kind: .profitable) : nil
        return (points, marker, frozen.horizon)
    }

    var body: some View {
        let (points, marker, horizon) = shown
        let y = frozen.map { (lo: $0.lo, hi: $0.hi, ticks: Self.ticks($0.lo, $0.hi)) } ?? yAxis(points)
        VStack(alignment: .leading, spacing: 4) {
            Text("Cash balance").font(.system(size: 11)).foregroundStyle(.secondary)
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("Month", p.t), y: .value("Cash", p.balance))
                        .foregroundStyle(color.opacity(0.1))
                    LineMark(x: .value("Month", p.t), y: .value("Cash", p.balance))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.primary.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1))
                if let m = marker {
                    // What happened goes along the top edge, over the marker (an invisible
                    // point at the top carries it); when and how much sits right above the
                    // dot. A dip has clear air above its low point. Out of cash ends a falling
                    // line that arrives from the upper left, so its date hangs right, into the
                    // empty space past the end, instead of sitting on the line.
                    PointMark(x: .value("Month", m.t), y: .value("Cash", y.hi))
                        .symbolSize(0)
                        .annotation(position: .bottom, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            markerLabel(m.kind == .profitable ? "Profitable" : "Out of cash")
                        }
                    PointMark(x: .value("Month", m.t), y: .value("Cash", m.balance))
                        .symbol { dot }
                        .annotation(position: m.kind == .profitable ? .top : .topTrailing, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            markerLabel(m.kind == .profitable
                                ? "\(formatMonthYear(months: m.t, from: now)) · \(formatMoney(m.balance))"
                                : formatMonthYear(months: m.t, from: now))
                        }
                }
                if let h = hover, frozen == nil {
                    RuleMark(x: .value("Month", h.t)).foregroundStyle(Color.primary.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Month", h.t), y: .value("Cash", h.balance))
                        .symbol { dot }
                        .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            tooltip(h)
                        }
                }
            }
            .chartXScale(domain: 0...horizon)
            .chartYScale(domain: y.lo...y.hi)
            .chartXAxis {
                let ticks = Self.xTicks(horizon)
                AxisMarks(values: ticks) { value in
                    let v = value.as(Double.self) ?? 0
                    let last = v == ticks.last
                    // Edge labels hang inward, as in the mock: a centered "0" collided with the
                    // y-axis labels and was dropped, and the last label (with " mo") near the
                    // right edge got truncated to "1…".
                    let anchor: UnitPoint = v == 0 ? .topLeading : last && horizon - v < horizon * 0.1 ? .topTrailing : .top
                    AxisValueLabel(anchor: anchor) {
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
                            guard frozen == nil, case let .active(location) = phase, let frame = proxy.plotFrame,
                                  let t: Double = proxy.value(atX: location.x - geo[frame].origin.x)
                            else { hover = nil; return }
                            hover = points.min { abs($0.t - t) < abs($1.t - t) }
                        }
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            drag(value, proxy: proxy, geo: geo, marker: marker, horizon: horizon, y: (y.lo, y.hi))
                        }.onEnded { _ in
                            guard frozen != nil else { return }
                            frozen = nil
                            onDrag(nil)
                        })
                        .onAppear { probe(proxy, geo, marker) }
                        .onChange(of: marker) { probe(proxy, geo, marker) }
                        // The window resizes after the dot moves (the chart appearing, say),
                        // which moves the dot on screen without changing it.
                        .onChange(of: geo.frame(in: .global)) { probe(proxy, geo, marker) }
                }
            }
            .font(.system(size: 10).monospacedDigit())
            .frame(height: Style.chartHeight + 18)
            // The top tick label sits centered on the top gridline, so it needs headroom
            // under the caption.
            .padding(.top, 6)
        }
    }

    private func drag(_ value: DragGesture.Value, proxy: ChartProxy, geo: GeometryProxy, marker: BalanceCurve.Marker?,
                      horizon: Double, y: (lo: Double, hi: Double)) {
        guard let plot = proxy.plotFrame else { return }
        let frame = geo[plot]
        if frozen == nil {
            // Only a press on the profitability dot starts a drag.
            guard let m = marker, m.kind == .profitable,
                  let dx = proxy.position(forX: m.t), let dy = proxy.position(forY: m.balance),
                  hypot(value.startLocation.x - frame.minX - dx, value.startLocation.y - frame.minY - dy) <= 12
            else { return }
            hover = nil
            frozen = Domain(horizon: horizon, lo: y.lo, hi: y.hi)
        }
        guard let domain = frozen,
              let t: Double = proxy.value(atX: value.location.x - frame.minX),
              let b: Double = proxy.value(atY: value.location.y - frame.minY),
              let moved = dragProfitPoint(to: t, balance: b, inputs: inputs, pointsPerMonth: frame.width / domain.horizon,
                                          pointsPerDollar: frame.height / (domain.hi - domain.lo))
        else { return }
        if moved.monthsToProfitability > domain.horizon * 0.92 {
            frozen?.horizon = moved.monthsToProfitability / 0.85
        }
        onDrag(moved)
    }

    /// For `make selftest`: where the dot is, in window coordinates.
    private func probe(_ proxy: ChartProxy, _ geo: GeometryProxy, _ marker: BalanceCurve.Marker?) {
        guard let m = marker, m.kind == .profitable, let plot = proxy.plotFrame,
              let dx = proxy.position(forX: m.t), let dy = proxy.position(forY: m.balance)
        else { return SelfTestProbe.profitDot = nil }
        let frame = geo.frame(in: .global)
        SelfTestProbe.profitDot = CGPoint(x: frame.minX + geo[plot].minX + dx, y: frame.minY + geo[plot].minY + dy)
    }

    /// Filled dot with a ring in the window color, so it stays legible on the line.
    private var dot: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
    }

    private func markerLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
    }

    /// The balance and the day, then the revenue and burn rates there, in the Revenue box's
    /// unit.
    private func tooltip(_ p: BalanceCurve.Point) -> some View {
        let revenue = revenueAt(inputs, months: p.t)
        let net = revenue - inputs.monthlyExpenses
        let short = switch revenueUnit {
        case .week: "wk"
        case .month: "mo"
        case .year: "yr"
        }
        let rate = { (monthly: Double) in "\(formatMoney(amountToUnit(monthly, revenueUnit)))/\(short)" }
        return VStack(alignment: .leading, spacing: 1) {
            (Text(formatMoney(p.balance)).font(.system(size: 12, weight: .semibold)).foregroundColor(.primary)
                + Text("  " + formatDate(months: p.t, from: now)))
            Text("Revenue \(rate(revenue))")
            Text("\(net < 0 ? "Burn" : "Profit") \(rate(abs(net)))")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
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

    private static func xTicks(_ horizon: Double) -> [Double] {
        Array(stride(from: 0, through: horizon + 1e-9, by: niceStep(horizon, 4)))
    }

    private static func ticks(_ lo: Double, _ hi: Double) -> [Double] {
        let step = niceStep(hi - lo, 3)
        return Array(stride(from: lo, through: hi + step / 2, by: step))
    }

    private func yAxis(_ points: [BalanceCurve.Point]) -> (lo: Double, hi: Double, ticks: [Double]) {
        let balances = points.map(\.balance)
        let lo0 = min(0, balances.min() ?? 0), hi0 = max(balances.max() ?? 1, 1)
        let step = Self.niceStep(hi0 - lo0, 3)
        let lo = (lo0 / step).rounded(.down) * step, hi = (hi0 / step).rounded(.up) * step
        return (lo, hi, Self.ticks(lo, hi))
    }
}

/// What `make selftest` needs to find in the window.
@MainActor
enum SelfTestProbe {
    static var profitDot: CGPoint?
    static var growthOutline: String?
    /// Each row's week/month/year toggle, in SwiftUI's global space.
    static var unitToggles: [Row: CGRect] = [:]
}
