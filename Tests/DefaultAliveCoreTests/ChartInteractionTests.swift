import Foundation
import Testing
@testable import DefaultAliveCore

private func close(_ a: Double?, _ b: Double, within tolerance: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

@Suite("Dragging the profitability point")
struct DragTests {
    // E 80k, R 20k: every growth rate's profitability point (T, cash − C) lies on one line,
    // since C = k·T with k = E − (E−R)/ln(E/R) for compounding growth.
    private let alive = Inputs(cash: 1_200_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 0.08)
    private let k = 80_000 - 60_000 / log(4.0)

    @Test func onTheLineGivesThatPoint() throws {
        let d = try #require(dragProfitPoint(to: 12, balance: 1_200_000 - k * 12, inputs: alive, pointsPerMonth: 10, pointsPerDollar: 1e-4))
        #expect(close(d.monthsToProfitability, 12, within: 1e-9))
        #expect(close(d.monthlyGrowth, pow(4, 1.0 / 12) - 1, within: 1e-12))
        #expect(!d.pinned)
        // And growth at that rate really does reach profitability at T = 12.
        var check = alive
        check.monthlyGrowth = d.monthlyGrowth
        #expect(close(project(check)?.monthsToProfitability, 12, within: 1e-9))
    }

    /// Off the line: the nearest point in screen space, so the axes' scales matter.
    @Test func offTheLineProjectsInScreenSpace() throws {
        let d = try #require(dragProfitPoint(to: 12, balance: 1_200_000, inputs: alive, pointsPerMonth: 10, pointsPerDollar: 1e-4))
        #expect(close(d.monthsToProfitability, 100 * 12 / (100 + k * k * 1e-8), within: 1e-9))
    }

    /// Down to the zero line and no further: the growth there is the default-alive minimum.
    @Test func pinsAtZeroBalance() throws {
        let d = try #require(dragProfitPoint(to: 60, balance: -500_000, inputs: alive, pointsPerMonth: 10, pointsPerDollar: 1e-4))
        #expect(d.pinned)
        #expect(close(d.monthsToProfitability, 1_200_000 / k, within: 1e-9))
        #expect(close(d.balance, 0, within: 1e-6))
        #expect(close(d.monthlyGrowth, 0.043332, within: 1e-6))
    }

    @Test func clampsTimeToTheVisibleRange() throws {
        let left = try #require(dragProfitPoint(to: 0, balance: 1_200_000, inputs: alive, pointsPerMonth: 10, pointsPerDollar: 1e-4))
        #expect(left.monthsToProfitability == 0.5)
        let right = try #require(dragProfitPoint(to: 25, balance: 1_200_000 - k * 25, inputs: alive, pointsPerMonth: 10,
                                                 pointsPerDollar: 1e-4, maxMonths: 20))
        #expect(right.monthsToProfitability == 20)
    }

    @Test func linearGrowth() throws {
        let linear = Inputs(cash: 400_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 5_000, linear: true)
        // C = (E−R)·T/2, so k = 30k; T = 10 needs +6k a month.
        let d = try #require(dragProfitPoint(to: 10, balance: 400_000 - 30_000 * 10, inputs: linear, pointsPerMonth: 10, pointsPerDollar: 1e-4))
        #expect(close(d.monthlyGrowth, 6_000, within: 1e-9))
    }

    @Test func noLineWithoutAPathToProfit() {
        var profitable = alive
        profitable.monthlyRevenue = 90_000
        #expect(dragProfitPoint(to: 5, balance: 0, inputs: profitable, pointsPerMonth: 10, pointsPerDollar: 1e-4) == nil)
        var noRevenue = alive
        noRevenue.monthlyRevenue = 0
        #expect(dragProfitPoint(to: 5, balance: 0, inputs: noRevenue, pointsPerMonth: 10, pointsPerDollar: 1e-4) == nil)
    }
}

@Suite("Revenue over time")
struct RevenueAtTests {
    @Test func compoundingAndLinear() {
        #expect(close(revenueAt(Inputs(cash: 0, monthlyExpenses: 0, monthlyRevenue: 20_000, monthlyGrowth: 0.08), months: 12),
                      20_000 * pow(1.08, 12), within: 1e-6))
        #expect(revenueAt(Inputs(cash: 0, monthlyExpenses: 0, monthlyRevenue: 20_000, monthlyGrowth: 5_000, linear: true), months: 12) == 80_000)
        // Shrinking linear revenue stops at zero.
        #expect(revenueAt(Inputs(cash: 0, monthlyExpenses: 0, monthlyRevenue: 20_000, monthlyGrowth: -2_000, linear: true), months: 15) == 0)
    }
}

@Suite("Setting growth from the chart")
struct SetGrowthTests {
    @Test func writesTheBoxAndKeepsTheExactValue() {
        var s = CalculatorState(input: RawInputs(cash: "1.2M", expenses: "80k", revenue: "20k", growth: "8"))
        s.setGrowth(monthly: 0.1)
        #expect(s.field(.growth).text == "10")
        #expect(s.inputs?.monthlyGrowth == 0.1)
        s.cycleUnit(.growth)
        #expect(s.field(.growth).text == "214")
        #expect(s.inputs?.monthlyGrowth == 0.1)
        s.toggleGrowthKind()
        s.setGrowth(monthly: 5_000)
        // The box is still per year (cycled above): +5k/mo a month is +720k/yr a year.
        #expect(s.field(.growth).text == "720k")
    }
}
