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

/// If `text` is arithmetic ("163+5"), its exact result ("168", "85000", "333.3333"); nil
/// for plain numbers and anything that doesn't evaluate. Raw like all box text: the box
/// draws the thousands commas and the unit ($ or %) itself.
public func compactField(_ row: Row, text: String, linear: Bool) -> String? {
    let t = text.trimmingCharacters(in: .whitespaces)
    // An operator after the first character (a leading "-" is just a sign) or a "(".
    guard t.first == "(" || t.dropFirst().contains(where: { "+-*/×÷()".contains($0) }) else { return nil }
    guard let v = evaluate(t, percent: row == .growth && !linear) else { return nil }
    return trimZeros(String(format: "%.4f", (v * 10_000).rounded() / 10_000))
}

/// What a box holds for what was typed or pasted: "$", "%" and "," dropped. The box draws
/// the unit and the thousands commas itself, so they're never characters you'd have to
/// delete, and the stored text never disagrees with what's on screen.
public func normalizeField(_ text: String) -> String {
    text.filter { $0 != "$" && $0 != "%" && $0 != "," }
}

/// Where a box draws a thousands comma: before these UTF-16 offsets of `text`. Every
/// number's whole part is grouped in threes; decimals aren't.
public func groupBreaks(_ text: String) -> [Int] {
    let units = Array(text.utf16)
    let zero = UInt16(UInt8(ascii: "0")), nine = UInt16(UInt8(ascii: "9")), point = UInt16(UInt8(ascii: "."))
    var breaks: [Int] = []
    var i = 0
    while i < units.count {
        guard (zero...nine).contains(units[i]) else { i += 1; continue }
        let start = i
        while i < units.count, (zero...nine).contains(units[i]) { i += 1 }
        let length = i - start
        if length >= 4, start == 0 || units[start - 1] != point {
            var at = start + (length % 3 == 0 ? 3 : length % 3)
            while at < i {
                breaks.append(at)
                at += 3
            }
        }
    }
    return breaks
}

/// `text` with the commas a box would draw, for places that show it as plain text.
public func groupedText(_ text: String) -> String {
    var out = Array(text.utf16)
    for at in groupBreaks(text).reversed() { out.insert(UInt16(UInt8(ascii: ",")), at: at) }
    return String(decoding: out, as: UTF16.self)
}

/// Where the cursor goes after normalizeField dropped characters from `old`: after the
/// same number of surviving characters. UTF-16 offsets, as NSRange and DOM selection use.
public func caretAfterNormalizing(_ old: String, caret: Int, _ new: String) -> Int {
    let dropped = Set("$%,".utf16)
    let kept = old.utf16.prefix(caret).filter { !dropped.contains($0) }.count
    return min(kept, new.utf16.count)
}
