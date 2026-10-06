import Foundation

private let suffixes: [Character: Double] = ["k": 1e3, "m": 1e6, "b": 1e9]

/// "250k", "$1.2M", "1,500", "  7 ", "-$1.6k", and arithmetic on those ("163+5",
/// "(20k+5k)*2") → number. nil if it isn't one.
public func parseAmount(_ text: String) -> Double? {
    evaluate(text, percent: false)
}

/// "8", "8%", "-3", "8+2" → fraction (0.08, 0.08, −0.03, 0.10). nil if it isn't a number.
public func parsePercent(_ text: String) -> Double? {
    evaluate(text, percent: true).map { $0 / 100 }
}

/// Arithmetic over the boxes' number syntax: + − * / × ÷ and parentheses, with unary minus
/// only at the start of an expression or a parenthesis, so "--5" and "5--3" stay invalid
/// rather than quietly meaning something. Amounts take "$" and k/m/b; percentages take "%".
func evaluate(_ text: String, percent: Bool) -> Double? {
    var parser = Arithmetic(chars: Array(text), percent: percent)
    return parser.parse()
}

private struct Arithmetic {
    let chars: [Character]
    let percent: Bool
    var i = 0

    init(chars: [Character], percent: Bool) {
        self.chars = chars
        self.percent = percent
    }

    mutating func peek() -> Character? {
        while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
        return i < chars.count ? chars[i] : nil
    }

    mutating func parse() -> Double? {
        guard let v = expression(), peek() == nil, v.isFinite else { return nil }
        return v
    }

    mutating func expression() -> Double? {
        let negate = peek() == "-"
        if negate { i += 1 }
        guard var value = term() else { return nil }
        if negate { value = -value }
        while let op = peek(), op == "+" || op == "-" {
            i += 1
            guard let rhs = term() else { return nil }
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }

    mutating func term() -> Double? {
        guard var value = factor() else { return nil }
        while let op = peek(), "*×/÷".contains(op) {
            i += 1
            guard let rhs = factor() else { return nil }
            value = op == "*" || op == "×" ? value * rhs : value / rhs
            guard value.isFinite else { return nil }
        }
        return value
    }

    mutating func factor() -> Double? {
        guard peek() == "(" else { return number() }
        i += 1
        guard let v = expression(), peek() == ")" else { return nil }
        i += 1
        return v
    }

    mutating func number() -> Double? {
        if !percent, peek() == "$" { i += 1 }
        _ = peek()
        let start = i
        while i < chars.count, chars[i].isASCII, chars[i].isNumber || chars[i] == "." || chars[i] == "," { i += 1 }
        guard let n = plainNumber(String(chars[start..<i]).replacingOccurrences(of: ",", with: "")) else { return nil }
        if percent {
            if peek() == "%" { i += 1 }
            return n
        }
        if i < chars.count, let scale = suffixes[Character(chars[i].lowercased())] {
            i += 1
            return n * scale
        }
        return n
    }
}

/// Digits with at most one decimal point. Double(String) alone also accepts "inf", "nan",
/// "1e3" and hex, none of which belong in a money field.
private func plainNumber(_ s: String) -> Double? {
    guard s.contains(where: { $0.isASCII && $0.isNumber }),
          s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
          s.filter({ $0 == "." }).count <= 1
    else { return nil }
    return Double(s)
}

/// If `text` is arithmetic ("163+5"), its result in the field's shortest exact form
/// ("168", "85k", "10%", "$2k"); nil for plain numbers and anything that doesn't evaluate.
/// A typed "$" survives; $ growth always shows one, % growth always a "%".
public func compactField(_ row: Row, text: String, linear: Bool) -> String? {
    let t = text.trimmingCharacters(in: .whitespaces)
    // An operator after the first character (a leading "-" is just a sign) or a "(".
    guard t.first == "(" || t.dropFirst().contains(where: { "+-*/×÷()".contains($0) }) else { return nil }
    let percent = row == .growth && !linear
    guard let v = evaluate(t, percent: percent) else { return nil }
    let sign = v < 0 ? "-" : ""
    if percent { return sign + compactNumber(abs(v)) + "%" }
    let dollar = (row == .growth && linear) || t.hasPrefix("$") || t.hasPrefix("-$")
    return sign + (dollar ? "$" : "") + compactNumber(abs(v))
}

/// Shortest exact spelling: 168, 85k, 1.234k, 1.2M; otherwise up to four decimals.
private func compactNumber(_ a: Double) -> String {
    for (scale, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "k")] where a >= scale {
        let x = a / scale
        let r = (x * 1000).rounded() / 1000
        if abs(x - r) < 1e-9 * max(1, x) { return trimZeros(String(format: "%.3f", r)) + suffix }
    }
    return trimZeros(String(format: "%.4f", (a * 10_000).rounded() / 10_000))
}
