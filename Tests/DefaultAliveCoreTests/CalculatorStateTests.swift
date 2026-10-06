import Foundation
import Testing
@testable import DefaultAliveCore

@Suite("Calculator state")
struct CalculatorStateTests {
    private let now = Date(timeIntervalSince1970: 1_768_000_000)

    private func filled(_ growth: String = "8%") -> CalculatorState {
        CalculatorState(input: RawInputs(cash: "$400k", expenses: "80k", revenue: "20k", growth: growth))
    }

    @Test func cyclingAUnitRoundTripsTheTypedTextAndNeverMovesTheAnswer() {
        var s = filled()
        let before = s.readout(now: now)
        s.cycleUnit(.expenses)
        #expect(s.expenses.unit == .year)
        #expect(s.expenses.text == "960k")
        #expect(s.readout(now: now).line1 == before.line1)
        s.cycleUnit(.expenses)
        #expect(s.expenses.text == "18.4k")
        #expect(s.readout(now: now).line1 == before.line1)
        s.cycleUnit(.expenses)
        #expect(s.expenses.unit == .month)
        #expect(s.expenses.text == "80k")
        #expect(s.readout(now: now) == before)
    }

    @Test func flippingGrowthKindSeedsAnEmptyBoxOnce() {
        var s = filled()
        s.toggleGrowthKind()
        #expect(s.linear)
        #expect(s.field(.growth).text == "1.6k")
    }

    @Test func eachGrowthKindKeepsItsOwnInput() {
        var s = filled()
        s.toggleGrowthKind()
        s.edit(.growth, text: "$5k")
        s.toggleGrowthKind()
        #expect(s.field(.growth).text == "8")
        s.toggleGrowthKind()
        #expect(s.field(.growth).text == "5k")
        s.edit(.growth, text: "")
        s.toggleGrowthKind()
        #expect(s.field(.growth).text == "8")
    }

    // Regression: re-deriving $ from the original % on each unit click moved the answer,
    // because the % → $ step depends on the period.
    @Test func cyclingDollarGrowthUnitKeepsTheAnswer() {
        var s = filled()
        s.toggleGrowthKind()
        let before = s.readout(now: now)
        s.cycleUnit(.growth)
        // +1.6k of MRR a month is +19.2k of MRR a year.
        #expect(s.field(.growth).text == "19.2k")
        #expect(s.readout(now: now).line1 == before.line1)
    }

    // $ growth adds to the Revenue box's figure, so changing that box's unit re-expresses it.
    @Test func revenueUnitChangeReExpressesDollarGrowth() {
        var s = filled()
        s.toggleGrowthKind()
        #expect(s.field(.growth).text == "1.6k")
        let before = s.readout(now: now)
        s.cycleUnit(.revenue)
        #expect(s.revenue.text == "240k")
        // +1.6k of MRR a month is +19.2k of annual revenue a month.
        #expect(s.field(.growth).text == "19.2k")
        #expect(s.readout(now: now).line1 == before.line1)
        s.cycleUnit(.revenue)
        s.cycleUnit(.revenue)
        #expect(s.field(.growth).text == "1.6k")
        #expect(s.readout(now: now) == before)
    }

    @Test func editingDropsTheRememberedOrigin() {
        var s = filled()
        s.cycleUnit(.expenses)
        s.edit(.expenses, text: "1M")
        s.cycleUnit(.expenses)
        s.cycleUnit(.expenses)
        s.cycleUnit(.expenses)
        #expect(s.expenses.unit == .year)
        #expect(s.expenses.text == "1M")
    }

    @Test func arrowsStepWithoutWrapping() {
        #expect(Row.cash.stepped(down: true) == .expenses)
        #expect(Row.growth.stepped(down: true) == .growth)
        #expect(Row.cash.stepped(down: false) == .cash)
        #expect(Row.revenue.stepped(down: false) == .expenses)
        // Tab still wraps.
        #expect(Row.growth.moved(forward: true) == .cash)
    }

    @Test func expressionsCountLiveAndCompactOnCommit() {
        var s = filled()
        let plain = s.readout(now: now)
        s.edit(.expenses, text: "60k+20k")
        #expect(s.readout(now: now) == plain)
        #expect(s.expenses.text == "60k+20k")
        s.commit(.expenses)
        #expect(s.expenses.text == "80000")
        s.commit(.expenses)
        #expect(s.expenses.text == "80000")
    }

    @Test func clearEmptiesBothGrowthKinds() {
        var s = filled()
        s.toggleGrowthKind()
        #expect(s.field(.growth).text == "1.6k")
        s.clear()
        #expect(Row.allCases.allSatisfy { s.field($0).text.isEmpty })
        s.toggleGrowthKind()
        #expect(s.field(.growth).text.isEmpty)
    }

    @Test func invalidOnlyWhenTextCantBeANumber() {
        var s = CalculatorState()
        #expect(!s.isInvalid(.revenue))
        s.edit(.revenue, text: "abc")
        #expect(s.isInvalid(.revenue))
        s.edit(.growth, text: "8%")
        #expect(!s.isInvalid(.growth))
        s.toggleGrowthKind()
        // The box draws the unit, so a typed "%" is just dropped: this is $8.
        s.edit(.growth, text: "8%")
        #expect(!s.isInvalid(.growth) && s.field(.growth).text == "8")
        s.edit(.growth, text: "8x")
        #expect(s.isInvalid(.growth))
    }

    // Box text is raw; the commas are drawn (groupBreaks), never stored.
    @Test func editingKeepsTextRaw() {
        var s = CalculatorState()
        s.edit(.cash, text: "1000000")
        #expect(s.cash.text == "1000000")
        #expect(fieldValue(.cash, text: s.cash.text, unit: .month, linear: false) == 1_000_000)
        s.edit(.cash, text: "$163000+5")
        #expect(s.cash.text == "163000+5")
        #expect(CalculatorState(input: RawInputs(cash: "$1200000", expenses: "80k", revenue: "20k", growth: "8%")).cash.text == "1200000")
    }
}
