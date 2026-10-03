import Foundation
import Testing
@testable import DefaultAliveCore

private func close(_ a: Double?, _ b: Double, within tolerance: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

@Suite("Projection")
struct ProjectionTests {
    // growth.tlb.org defaults: $100/wk revenue growing 2.5%/wk against $1600/wk flat
    // expenses. Its own calc(), run in node, gives these two numbers. The model is
    // continuous, so the same business entered monthly (TLB uses 365.2425/7/12 weeks
    // per month) must land on exactly the same answer.
    @Test func matchesTLBReference() throws {
        let weeksPerMonth = 365.2425 / 7 / 12
        let inputs = Inputs(
            cash: 0,
            monthlyExpenses: 1600 * weeksPerMonth,
            monthlyRevenue: 100 * weeksPerMonth,
            monthlyGrowth: pow(1.025, weeksPerMonth) - 1
        )
        let p = try #require(project(inputs))
        #expect(close(p.monthsToProfitability, 25.823576392986606, within: 1e-6))
        #expect(close(p.capitalNeeded, 118_907.70751121586, within: 1))
    }

    @Test func matchesClosedForm() throws {
        let p = try #require(project(Inputs(cash: 1_000_000, monthlyExpenses: 50_000, monthlyRevenue: 10_000, monthlyGrowth: 0.10)))
        let T = log(5) / log(1.1)
        let C = 50_000 * T - 40_000 / log(1.1)
        #expect(p.verdict == .alive)
        #expect(close(p.monthsToProfitability, T, within: 1e-9))
        #expect(close(p.capitalNeeded, C, within: 1e-6))
        #expect(close(p.cushion, 1_000_000 - C, within: 1e-6))
        #expect(p.runwayMonths == nil)
    }

    @Test func burnCurveEndsAtCapitalNeeded() throws {
        let inputs = Inputs(cash: 0, monthlyExpenses: 50_000, monthlyRevenue: 10_000, monthlyGrowth: 0.10)
        let p = try #require(project(inputs))
        #expect(cumulativeBurn(inputs, months: 0) == 0)
        #expect(close(cumulativeBurn(inputs, months: p.monthsToProfitability!), p.capitalNeeded!, within: 1e-6))
    }

    @Test func verdictFlipsAtCapitalNeeded() throws {
        let base = Inputs(cash: 0, monthlyExpenses: 50_000, monthlyRevenue: 10_000, monthlyGrowth: 0.10)
        let C = try #require(project(base)?.capitalNeeded)
        let T = log(5) / log(1.1)

        var rich = base
        rich.cash = C + 1
        let alive = try #require(project(rich))
        #expect(alive.verdict == .alive)
        #expect(close(alive.cushion, 1, within: 1e-6))
        #expect(alive.runwayMonths == nil)

        var poor = base
        poor.cash = C - 1
        let dead = try #require(project(poor))
        #expect(dead.verdict == .dead)
        #expect(close(dead.cushion, -1, within: 1e-6))
        let runway = try #require(dead.runwayMonths)
        #expect(runway > 0 && runway < T)
    }

    @Test(arguments: [60_000.0, 50_000.0])
    func alreadyProfitableIsAliveWithNoCash(revenue: Double) throws {
        let p = try #require(project(Inputs(cash: 0, monthlyExpenses: 50_000, monthlyRevenue: revenue, monthlyGrowth: 0.05)))
        #expect(p.verdict == .alive)
        #expect(p.monthsToProfitability == 0)
        #expect(p.capitalNeeded == 0)
        #expect(p.cushion == 0)
        #expect(p.runwayMonths == nil)
    }

    @Test func zeroGrowthWhileBurningIsDead() throws {
        let p = try #require(project(Inputs(cash: 300_000, monthlyExpenses: 50_000, monthlyRevenue: 20_000, monthlyGrowth: 0)))
        #expect(p.verdict == .dead)
        #expect(p.monthsToProfitability == nil)
        #expect(p.capitalNeeded == nil)
        #expect(p.cushion == nil)
        #expect(close(p.runwayMonths, 10, within: 1e-9))
    }

    @Test func shrinkingRevenueRunsOutSooner() throws {
        let inputs = Inputs(cash: 300_000, monthlyExpenses: 50_000, monthlyRevenue: 20_000, monthlyGrowth: -0.05)
        let p = try #require(project(inputs))
        #expect(p.verdict == .dead)
        #expect(p.monthsToProfitability == nil)
        let runway = try #require(p.runwayMonths)
        #expect(runway < 10)
        #expect(close(cumulativeBurn(inputs, months: runway), 300_000, within: 0.01))
    }

    @Test func deadWithGrowthRunsOutBeforeProfitability() throws {
        let inputs = Inputs(cash: 100_000, monthlyExpenses: 50_000, monthlyRevenue: 10_000, monthlyGrowth: 0.10)
        let p = try #require(project(inputs))
        let T = log(5) / log(1.1)
        #expect(p.verdict == .dead)
        #expect(close(p.monthsToProfitability, T, within: 1e-9))
        #expect(close(p.cushion, 100_000 - p.capitalNeeded!, within: 1e-6))
        let runway = try #require(p.runwayMonths)
        #expect(runway > 0 && runway < T)
        #expect(close(cumulativeBurn(inputs, months: runway), 100_000, within: 0.01))
    }

    @Test(arguments: [0.10, 0.0, -0.05])
    func noCashWhileBurningIsDeadNow(growth: Double) throws {
        let p = try #require(project(Inputs(cash: 0, monthlyExpenses: 50_000, monthlyRevenue: 10_000, monthlyGrowth: growth)))
        #expect(p.verdict == .dead)
        #expect(p.runwayMonths == 0)
    }

    // Exponential growth from zero stays zero, however fast the rate.
    @Test func zeroRevenueNeverGetsProfitable() throws {
        let p = try #require(project(Inputs(cash: 300_000, monthlyExpenses: 50_000, monthlyRevenue: 0, monthlyGrowth: 0.20)))
        #expect(p.verdict == .dead)
        #expect(p.monthsToProfitability == nil)
        #expect(close(p.runwayMonths, 6, within: 1e-9))
    }

    @Test(arguments: [
        Inputs(cash: -1, monthlyExpenses: 50_000, monthlyRevenue: 10_000, monthlyGrowth: 0.1),
        Inputs(cash: 1, monthlyExpenses: -1, monthlyRevenue: 10_000, monthlyGrowth: 0.1),
        Inputs(cash: 1, monthlyExpenses: 50_000, monthlyRevenue: -1, monthlyGrowth: 0.1),
        Inputs(cash: 1, monthlyExpenses: 50_000, monthlyRevenue: 10_000, monthlyGrowth: -1),
        Inputs(cash: 1, monthlyExpenses: 50_000, monthlyRevenue: 10_000, monthlyGrowth: -1.5),
        Inputs(cash: .nan, monthlyExpenses: 50_000, monthlyRevenue: 10_000, monthlyGrowth: 0.1),
        Inputs(cash: .infinity, monthlyExpenses: 50_000, monthlyRevenue: 10_000, monthlyGrowth: 0.1),
    ])
    func invalidInputsHaveNoProjection(inputs: Inputs) {
        #expect(project(inputs) == nil)
    }
}
