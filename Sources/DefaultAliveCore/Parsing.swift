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

/// If `text` is arithmetic ("163+5"), its exact result with thousands separators ("168",
/// "85,000", "333.3333"); nil for plain numbers and anything that doesn't evaluate. The
/// box draws the unit ($ or %), so it's never part of the text.
public func compactField(_ row: Row, text: String, linear: Bool) -> String? {
    let t = text.trimmingCharacters(in: .whitespaces)
    // An operator after the first character (a leading "-" is just a sign) or a "(".
    guard t.first == "(" || t.dropFirst().contains(where: { "+-*/×÷()".contains($0) }) else { return nil }
    guard let v = evaluate(t, percent: row == .growth && !linear) else { return nil }
    return groupThousands(trimZeros(String(format: "%.4f", (v * 10_000).rounded() / 10_000)))
}

/// What a box shows for what was typed: "$" and "%" dropped (the box draws the unit) and
/// every number's whole part grouped in threes, live: "1000000" → "1,000,000",
/// "$163000+5" → "163,000+5". Decimals are left alone.
public func normalizeField(_ text: String) -> String {
    groupThousands(text.filter { $0 != "$" && $0 != "%" })
}

func groupThousands(_ text: String) -> String {
    var out = ""
    var run = ""
    var afterPoint = false
    func flush() {
        if afterPoint {
            out += run
        } else {
            let digits = Array(run.filter { $0 != "," })
            for (i, d) in digits.enumerated() {
                if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
                out.append(d)
            }
        }
        run = ""
    }
    for ch in text {
        if ch.isASCII, ch.isNumber || ch == "," {
            run.append(ch)
            continue
        }
        flush()
        out.append(ch)
        afterPoint = ch == "."
    }
    flush()
    return out
}

/// Where the cursor goes after normalizeField rewrote `old` into `new`: after the same
/// number of surviving characters (anything but "," "$" "%"). UTF-16 offsets, as NSRange
/// and DOM selection use.
public func caretAfterNormalizing(_ old: String, caret: Int, _ new: String) -> Int {
    let dropped: Set<UInt16> = [",", "$", "%"].map { Character($0).utf16.first! }.reduce(into: []) { $0.insert($1) }
    let kept = old.utf16.prefix(caret).filter { !dropped.contains($0) }.count
    let comma = Character(",").utf16.first!
    var seen = 0
    var i = 0
    for unit in new.utf16 {
        if seen == kept { break }
        if unit != comma { seen += 1 }
        i += 1
    }
    return i
}
