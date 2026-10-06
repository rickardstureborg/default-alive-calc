import Foundation
import Testing
@testable import DefaultAliveCore

@Suite("Taxes")
struct TaxTests {
    private let base = Inputs(cash: 400_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 0.08)
    private let assumptions = TaxAssumptions(oaklandShare: 1, washingtonShare: 0.1)

    @Test func belowWashingtonCreditOnlyOaklandReceiptsAndDelaware() {
        let t = withTaxes(base, assumptions)
        #expect(abs(t.revenueRate - 0.0036) < 1e-15)
        #expect(t.fixedMonthly == 37.5)
        #expect(abs(t.inputs.monthlyRevenue - 20_000 * (1 - 0.0036)) < 1e-9)
        #expect(t.inputs.monthlyExpenses == 80_037.5)
        #expect(t.inputs.monthlyGrowth == 0.08)
    }

    // $250k/mo is $3M/yr, $300k of it in Washington: past the B&O small business credit.
    @Test func overWashingtonCreditAddsBandO() {
        var big = base
        big.monthlyRevenue = 250_000
        let t = withTaxes(big, assumptions)
        #expect(abs(t.revenueRate - (0.0036 + 0.00471 * 0.1)) < 1e-15)
    }

    @Test func linearGrowthIsTaxedLikeRevenue() {
        let t = withTaxes(Inputs(cash: 400_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 5_000, linear: true), assumptions)
        #expect(abs(t.inputs.monthlyGrowth - 5_000 * (1 - 0.0036)) < 1e-9)
    }

    /// Gross breakevens, taxed again, land exactly on capital needed == cash.
    @Test func grossBreakevensRoundTrip() throws {
        let t = withTaxes(base, assumptions)
        let b = t.gross(breakevens(t.inputs))
        guard case let .value(revenue) = b.revenue, case let .value(expenses) = b.expenses else {
            Issue.record("expected values, got \(b)")
            return
        }
        var r = base; r.monthlyRevenue = revenue
        #expect(abs((project(withTaxes(r, assumptions).inputs)?.capitalNeeded ?? 0) - base.cash) < 1e-3)
        var e = base; e.monthlyExpenses = expenses
        #expect(abs((project(withTaxes(e, assumptions).inputs)?.capitalNeeded ?? 0) - base.cash) < 1e-3)
    }

    @Test func stateAppliesTaxesOnlyWhenTickedWithValidShares() {
        let now = Date(timeIntervalSince1970: 1_768_000_000)
        var s = CalculatorState(input: RawInputs(cash: "$400k", expenses: "80k", revenue: "20k", growth: "8%"))
        let off = s.readout(now: now)
        #expect(s.taxSummary == "")
        s.taxesOn = true
        #expect(s.taxAssumptions == TaxAssumptions(oaklandShare: 1, washingtonShare: 0.1))
        #expect(s.readout(now: now).hints.cash == "≥ $665k")
        #expect(s.taxSummary == "≈ 0.36% + $450/yr")
        s.oaklandShare = "abc"
        #expect(s.taxAssumptions == nil)
        #expect(s.readout(now: now) == off)
    }
}
