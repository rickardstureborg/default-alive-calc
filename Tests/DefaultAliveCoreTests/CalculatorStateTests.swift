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
        #expect(s.readout(now: now).line2 == before.line2)
        s.cycleUnit(.expenses)
        #expect(s.expenses.text == "18.4k")
        #expect(s.readout(now: now).line2 == before.line2)
        s.cycleUnit(.expenses)
        #expect(s.expenses.unit == .month)
        #expect(s.expenses.text == "80k")
        #expect(s.readout(now: now) == before)
    }

    @Test func flippingGrowthKindSeedsAnEmptyBoxOnce() {
        var s = filled()
        s.toggleGrowthKind()
        #expect(s.linear)
        #expect(s.field(.growth).text == "$1.6k")
    }

    @Test func eachGrowthKindKeepsItsOwnInput() {
        var s = filled()
        s.toggleGrowthKind()
        s.edit(.growth, text: "$5k")
        s.toggleGrowthKind()
        #expect(s.field(.growth).text == "8%")
        s.toggleGrowthKind()
        #expect(s.field(.growth).text == "$5k")
        s.edit(.growth, text: "")
        s.toggleGrowthKind()
        #expect(s.field(.growth).text == "8%")
    }

    // Regression: re-deriving $ from the original % on each unit click moved the answer,
    // because the % → $ step depends on the period.
    @Test func cyclingDollarGrowthUnitKeepsTheAnswer() {
        var s = filled()
        s.toggleGrowthKind()
        let before = s.readout(now: now)
        s.cycleUnit(.growth)
        #expect(s.field(.growth).text == "$230k")
        #expect(s.readout(now: now).line2 == before.line2)
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
        #expect(s.expenses.text == "80k")
        s.commit(.expenses)
        #expect(s.expenses.text == "80k")
    }

    @Test func clearEmptiesBothGrowthKinds() {
        var s = filled()
        s.toggleGrowthKind()
        #expect(s.field(.growth).text == "$1.6k")
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
        s.edit(.growth, text: "8%")
        #expect(s.isInvalid(.growth))
    }
}
