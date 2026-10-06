import Foundation
import Testing
@testable import DefaultAliveCore

@Suite("Parsing")
struct ParsingTests {
    @Test(arguments: [
        ("250k", 250_000.0),
        ("$1.2M", 1_200_000),
        ("1,500", 1_500),
        ("  7 ", 7),
        ("1.5K", 1_500),
        (".5k", 500),
        ("2b", 2_000_000_000),
        ("$ 80k", 80_000),
        ("5.", 5),
        ("-$1.6k", -1_600),
    ])
    func amounts(text: String, expected: Double) throws {
        let value = try #require(parseAmount(text))
        #expect(abs(value - expected) < 1e-6)
    }

    @Test(arguments: ["", "abc", "1.2.3", "k", "$", "inf", "nan", "1e3", "12x", "--5", "$-5"])
    func nonAmounts(text: String) {
        #expect(parseAmount(text) == nil)
    }

    @Test(arguments: [
        ("8%", 0.08),
        ("8", 0.08),
        ("-3", -0.03),
        (" 2.5 % ", 0.025),
        ("0", 0),
    ])
    func percents(text: String, expected: Double) throws {
        let value = try #require(parsePercent(text))
        #expect(abs(value - expected) < 1e-12)
    }

    @Test(arguments: ["", "abc", "%", "1.2.3", "inf"])
    func nonPercents(text: String) {
        #expect(parsePercent(text) == nil)
    }
}

@Suite("Formatting")
struct FormattingTests {
    // Breakeven hints round toward the side that really flips the verdict.
    @Test(arguments: [
        (241.04, true, "$242"),
        (241.04, false, "$241"),
        (360_000, true, "$360k"),
        (7_461.06, false, "$7.46k"),
        (999.7, true, "$1k"),
        (1_234_567, true, "$1.24M"),
        (252_083.33, true, "$252.1k"),
        (0, true, "$0"),
    ])
    func moneyBounds(value: Double, up: Bool, expected: String) {
        #expect(formatMoneyBound(value, roundUp: up) == expected)
    }

    @Test(arguments: [(0.13571, "13.6%"), (0.0999999, "10%"), (0.0433, "4.33%"), (3.6, "360%")])
    func percentBoundsRoundUp(value: Double, expected: String) {
        #expect(formatPercentBound(value, roundUp: true) == expected)
    }

    @Test(arguments: [(0.0179, "1.79%"), (0.105, "10.5%"), (1.52, "152%"), (0.08, "8%")])
    func percents(value: Double, expected: String) {
        #expect(formatPercent(value) == expected)
    }

    @Test(arguments: [
        (270_000.0, "$270k"),
        (1_200_000, "$1.2M"),
        (950, "$950"),
        (0, "$0"),
        (1_500, "$1.5k"),
        (1_000_000, "$1M"),
        (999_999, "$1M"),
        (12_345_678, "$12.3M"),
        (2_500_000_000, "$2.5B"),
        (-130_000, "-$130k"),
        // Exact ties round away from zero, the same as Math.round in design/model.js.
        (1_250_000, "$1.3M"),
        (2_500, "$2.5k"),
        (999.5, "$1k"),
        (100_500, "$101k"),
    ])
    func money(value: Double, expected: String) {
        #expect(formatMoney(value) == expected)
    }

    @Test(arguments: [(18.0, "18.0 months"), (11.23, "11.2 months"), (0.04, "0.0 months"), (12.25, "12.3 months")])
    func months(value: Double, expected: String) {
        #expect(formatMonths(value) == expected)
    }

    @Test func monthYear() throws {
        let start = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15)))
        #expect(formatMonthYear(months: 3, from: start) == "Apr 2026")
        #expect(formatMonthYear(months: 27.25, from: start) == "Apr 2028")
        let endOfJanuary = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31)))
        #expect(formatMonthYear(months: 1, from: endOfJanuary) == "Feb 2026")
    }
}
