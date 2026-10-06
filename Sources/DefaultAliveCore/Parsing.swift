import Foundation

private let suffixes: [Character: Double] = ["k": 1e3, "m": 1e6, "b": 1e9]

/// "250k", "$1.2M", "1,500", "  7 ", "-$1.6k" → number. nil if it isn't one. The sign
/// goes before the "$" because that's how formatMoney writes negative $ growth back.
public func parseAmount(_ text: String) -> Double? {
    var s = text.trimmingCharacters(in: .whitespaces).lowercased()
    let negative = s.hasPrefix("-")
    if negative { s.removeFirst() }
    if s.hasPrefix("$") { s.removeFirst() }
    if s.hasPrefix("-") { return nil }
    s = s.replacingOccurrences(of: ",", with: "")
    var multiplier = 1.0
    if let last = s.last, let scale = suffixes[last] {
        multiplier = scale
        s.removeLast()
    }
    return plainNumber(s.trimmingCharacters(in: .whitespaces)).map { (negative ? -$0 : $0) * multiplier }
}

/// "8", "8%", "-3" → fraction (0.08, 0.08, −0.03). nil if it isn't a number.
public func parsePercent(_ text: String) -> Double? {
    var s = text.trimmingCharacters(in: .whitespaces)
    if s.hasSuffix("%") { s.removeLast() }
    return plainNumber(s.trimmingCharacters(in: .whitespaces)).map { $0 / 100 }
}

/// Digits with at most one decimal point and an optional leading minus. Double(String)
/// alone also accepts "inf", "nan", "1e3" and hex, none of which belong in a money field.
private func plainNumber(_ s: String) -> Double? {
    let body = s.hasPrefix("-") ? s.dropFirst() : Substring(s)
    guard body.contains(where: { $0.isASCII && $0.isNumber }),
          body.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
          body.filter({ $0 == "." }).count <= 1
    else { return nil }
    return Double(s)
}
