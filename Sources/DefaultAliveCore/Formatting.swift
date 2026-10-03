import Foundation

/// 950 → "$950", 15300 → "$15.3k", 270000 → "$270k", 1.2e6 → "$1.2M".
/// At most three significant digits: the inputs are estimates, so more would be false precision.
public func formatMoney(_ value: Double) -> String {
    let v = abs(value)
    if v < 0.5 { return "$0" }
    let sign = value < 0 ? "-" : ""
    // Thresholds sit just under each unit so 999,999 rounds up to "$1M", not "$1000k".
    for (scale, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "k")] where v >= scale - scale / 2000 {
        let x = v / scale
        let digits = x < 99.95 ? String(format: "%.1f", x) : String(format: "%.0f", x)
        let trimmed = digits.hasSuffix(".0") ? String(digits.dropLast(2)) : digits
        return "\(sign)$\(trimmed)\(suffix)"
    }
    return "\(sign)$\(String(format: "%.0f", v))"
}

/// 18 → "18.0 months".
public func formatMonths(_ months: Double) -> String {
    String(format: "%.1f months", months)
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
