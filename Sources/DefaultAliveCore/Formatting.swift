import Foundation

// design/model.js is a line-for-line twin of these. Rounding is explicit (ties away from
// zero, which is Math.round for positive numbers) rather than printf's "%.1f", which
// rounds exact ties to even while JS toFixed rounds them up: $1.25M would read "$1.2M"
// in the app and "$1.3M" in the browser.

private func oneDecimal(_ x: Double) -> String {
    String(format: "%.1f", (x * 10).rounded(.toNearestOrAwayFromZero) / 10)
}

/// 950 → "$950", 15300 → "$15.3k", 270000 → "$270k", 1.2e6 → "$1.2M".
/// At most three significant digits: the inputs are estimates, so more would be false precision.
public func formatMoney(_ value: Double) -> String {
    let v = abs(value)
    if v < 0.5 { return "$0" }
    let sign = value < 0 ? "-" : ""
    // Thresholds sit just under each unit so 999,999 rounds up to "$1M", not "$1000k".
    for (scale, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "k")] where v >= scale - scale / 2000 {
        let x = v / scale
        let digits = x < 99.95 ? oneDecimal(x) : String(Int(x.rounded(.toNearestOrAwayFromZero)))
        let trimmed = digits.hasSuffix(".0") ? String(digits.dropLast(2)) : digits
        return "\(sign)$\(trimmed)\(suffix)"
    }
    return "\(sign)$\(Int(v.rounded(.toNearestOrAwayFromZero)))"
}

/// 18 → "18.0 months".
public func formatMonths(_ months: Double) -> String {
    "\(oneDecimal(months)) months"
}

func trimZeros(_ s: String) -> String {
    guard s.contains(".") else { return s }
    var t = s
    while t.hasSuffix("0") { t.removeLast() }
    if t.hasSuffix(".") { t.removeLast() }
    return t
}

private func percentPlaces(_ v: Double) -> Int { abs(v) >= 100 ? 0 : abs(v) >= 10 ? 1 : 2 }

/// 0.0179 → "1.79%", 0.105 → "10.5%", 1.52 → "152%": three significant digits.
public func formatPercent(_ fraction: Double) -> String {
    let v = fraction * 100
    let f = pow(10, Double(percentPlaces(v)))
    return trimZeros(String(format: "%.\(percentPlaces(v))f", (v * f).rounded(.toNearestOrAwayFromZero) / f)) + "%"
}

// Breakeven hints round toward the safe side ("≥" up, "≤" down), so the shown value
// really flips the verdict: $241.04 needed must read "≥ $242", never "≥ $241". They also
// carry one more digit than formatMoney ($7.46k, $252.1k) so the rounding costs little.
// The 1e-9 slack keeps an exact grid value (360000) from stepping to the next one.
private let boundSteps: [(from: Double, step: Double)] = [(1e10, 1e8), (1e9, 1e7), (1e7, 1e5), (1e6, 1e4), (1e4, 100), (1e3, 10), (0, 1)]

private func directed(_ x: Double, up: Bool) -> Double {
    up ? (x - 1e-9).rounded(.up) : (x + 1e-9).rounded(.down)
}

/// Breakeven hint amount, rounded toward the safe side: "$242", "$7.46k", "$252.1k".
public func formatMoneyBound(_ value: Double, roundUp: Bool) -> String {
    let v = max(0, value)
    let step = boundSteps.first { v >= $0.from }!.step
    let r = directed(v / step, up: roundUp) * step
    for (scale, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "k")] where r >= scale {
        let x = r / scale
        return "$" + trimZeros(String(format: x < 10 ? "%.2f" : "%.1f", x)) + suffix
    }
    return "$" + String(Int(r))
}

/// Breakeven hint percentage, rounded toward the safe side: "13.6%", "4.34%".
public func formatPercentBound(_ fraction: Double, roundUp: Bool) -> String {
    let v = fraction * 100
    let places = percentPlaces(v)
    let f = pow(10, Double(places))
    return trimZeros(String(format: "%.\(places)f", directed(v * f, up: roundUp) / f)) + "%"
}

/// The calendar month `months` from `start`, e.g. "Apr 2028".
public func formatMonthYear(months: Double, from start: Date) -> String {
    let whole = Int(months.rounded(.down))
    let calendar = Calendar.current
    let base = calendar.date(byAdding: .month, value: whole, to: start) ?? start
    let date = base.addingTimeInterval((months - Double(whole)) * 30.436875 * 86_400)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = calendar
    formatter.dateFormat = "MMM yyyy"
    return formatter.string(from: date)
}
