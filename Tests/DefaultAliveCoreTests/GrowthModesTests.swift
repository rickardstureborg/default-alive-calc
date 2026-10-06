import Foundation
import Testing
@testable import DefaultAliveCore

private func close(_ a: Double?, _ b: Double, within tolerance: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

private func value(_ t: Threshold) -> Double? {
    if case let .value(v) = t { v } else { nil }
}

@Suite("Linear growth")
struct LinearTests {
    // E 80k, R 20k, +5k/mo: T = 60k/5k = 12, C = 60k²/(2·5k) = 360k.
    @Test func closedForms() throws {
        let p = try #require(project(Inputs(cash: 400_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 5_000, linear: true)))
        #expect(p.verdict == .alive)
        #expect(close(p.monthsToProfitability, 12, within: 1e-12))
        #expect(close(p.capitalNeeded, 360_000, within: 1e-6))
        #expect(close(p.cushion, 40_000, within: 1e-6))
    }

    @Test func deadRunwayIsWhereBurnHitsCash() throws {
        let inputs = Inputs(cash: 251_000, monthlyExpenses: 11_000, monthlyRevenue: 0, monthlyGrowth: 240, linear: true)
        let p = try #require(project(inputs))
        #expect(p.verdict == .dead)
        #expect(close(p.capitalNeeded, 11_000 * 11_000 / 480, within: 1e-6))
        let runway = try #require(p.runwayMonths)
        #expect(close(runway, 42.8287, within: 1e-4))
        #expect(close(cumulativeBurn(inputs, months: runway), 251_000, within: 1e-6))
    }

    // Unlike compounding, linear growth from zero revenue does get somewhere.
    @Test func zeroRevenueCanStillReachProfitability() throws {
        let p = try #require(project(Inputs(cash: 1_000_000, monthlyExpenses: 50_000, monthlyRevenue: 0, monthlyGrowth: 5_000, linear: true)))
        #expect(close(p.monthsToProfitability, 10, within: 1e-12))
    }

    @Test func flatRevenueRunsOutLinearly() throws {
        let p = try #require(project(Inputs(cash: 300_000, monthlyExpenses: 50_000, monthlyRevenue: 20_000, monthlyGrowth: 0, linear: true)))
        #expect(p.verdict == .dead)
        #expect(p.monthsToProfitability == nil)
        #expect(close(p.runwayMonths, 10, within: 1e-9))
    }

    // −2k/mo takes 20k of revenue to zero at month 10; after that all 80k burns.
    @Test func shrinkingRevenueStopsAtZero() throws {
        let inputs = Inputs(cash: 1_000_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: -2_000, linear: true)
        let p = try #require(project(inputs))
        let runway = try #require(p.runwayMonths)
        #expect(runway > 10)
        #expect(close(cumulativeBurn(inputs, months: runway), 1_000_000, within: 1e-6))
        #expect(close(cumulativeBurn(inputs, months: 12), cumulativeBurn(inputs, months: 10) + 2 * 80_000, within: 1e-6))
    }
}

@Suite("Units")
struct UnitsTests {
    @Test func periods() {
        #expect(Period.month.months == 1)
        #expect(Period.year.months == 12)
        #expect(close(Period.week.months, 12 * 7 / 365.2425, within: 1e-15))
        #expect(Period.week.next == .month)
        #expect(Period.month.next == .year)
        #expect(Period.year.next == .week)
    }

    @Test func conversions() {
        #expect(amountToUnit(80_000, .year) == 960_000)
        #expect(close(amountFromUnit(amountToUnit(80_000, .week), .week), 80_000, within: 1e-9))
        // Growth compounds per period: 8%/mo is 152%/yr, not 96%.
        #expect(close(growthToUnit(0.08, .year), pow(1.08, 12) - 1, within: 1e-12))
        #expect(close(growthFromUnit(growthToUnit(0.08, .week), .week), 0.08, within: 1e-12))
        // $ growth scales with period²: monthly revenue +5k each month = yearly revenue +720k each year.
        #expect(close(linearToUnit(5_000, .year), 720_000, within: 1e-9))
        #expect(close(linearFromUnit(linearToUnit(5_000, .week), .week), 5_000, within: 1e-9))
    }

    @Test func switchingGrowthKindKeepsTheFirstStep() throws {
        // 8% of $20k/mo is +$1.6k/mo.
        let dollars = try #require(switchGrowthKind(0.08, toLinear: true, monthlyRevenue: 20_000, unit: .month))
        #expect(close(dollars, 1_600, within: 1e-9))
        let back = try #require(switchGrowthKind(dollars, toLinear: false, monthlyRevenue: 20_000, unit: .month))
        #expect(close(back, 0.08, within: 1e-12))
        #expect(switchGrowthKind(0.08, toLinear: true, monthlyRevenue: 0, unit: .month) == nil)
    }

    @Test func fieldTextRoundTrips() throws {
        #expect(fieldText(.expenses, monthly: 80_000, unit: .week, linear: false) == "18.4k")
        #expect(fieldText(.growth, monthly: 0.08, unit: .year, linear: false) == "152%")
        #expect(fieldText(.growth, monthly: 1_600, unit: .month, linear: true) == "$1.6k")
        #expect(fieldText(.growth, monthly: -1_600, unit: .month, linear: true) == "-$1.6k")
        #expect(close(fieldValue(.growth, text: "-$1.6k", unit: .month, linear: true), -1_600, within: 1e-9))
        #expect(close(fieldValue(.expenses, text: "18.4k", unit: .week, linear: false), 18_400 / Period.week.months, within: 1e-6))
        #expect(fieldValue(.expenses, text: "-5", unit: .month, linear: false) == nil)
        #expect(fieldValue(.growth, text: "8%", unit: .month, linear: true) == nil)
    }
}

@Suite("Breakevens")
struct BreakevenTests {
    /// Plugging each threshold back in must land exactly on capital needed == cash.
    private func roundTrips(_ inputs: Inputs) throws {
        let b = breakevens(inputs)
        if let e = value(b.expenses), e > inputs.monthlyRevenue {
            var x = inputs; x.monthlyExpenses = e
            #expect(close(project(x)?.capitalNeeded, inputs.cash, within: 1e-3 * max(1, inputs.cash)))
        }
        if let r = value(b.revenue), r < inputs.monthlyExpenses {
            var x = inputs; x.monthlyRevenue = r
            #expect(close(project(x)?.capitalNeeded, inputs.cash, within: 1e-3 * max(1, inputs.cash)))
        }
        if let g = value(b.growth) {
            var x = inputs; x.monthlyGrowth = g
            #expect(close(project(x)?.capitalNeeded, inputs.cash, within: 1e-3 * max(1, inputs.cash)))
        }
        #expect(value(b.cash) == project(inputs)?.capitalNeeded)
    }

    @Test(arguments: [400_000.0, 1_200_000])
    func compoundingRoundTrips(cash: Double) throws {
        try roundTrips(Inputs(cash: cash, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 0.08))
    }

    @Test(arguments: [251_000.0, 400_000])
    func linearRoundTrips(cash: Double) throws {
        try roundTrips(Inputs(cash: cash, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 5_000, linear: true))
    }

    @Test func linearClosedForms() {
        // √(2·5000·400000) = 63,245.55: the revenue gap cash can carry to profitability.
        let b = breakevens(Inputs(cash: 400_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 5_000, linear: true))
        #expect(close(value(b.expenses), 20_000 + 63_245.553, within: 1e-3))
        #expect(close(value(b.revenue), 80_000 - 63_245.553, within: 1e-3))
        #expect(close(value(b.growth), 4_500, within: 1e-9))
        #expect(close(value(b.cash), 360_000, within: 1e-6))
    }

    @Test func neverAndAny() {
        let flat = breakevens(Inputs(cash: 600_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 0))
        #expect(flat.cash == .never)
        #expect(flat.expenses == .value(20_000))
        #expect(flat.revenue == .value(80_000))
        let zeroRevenue = breakevens(Inputs(cash: 600_000, monthlyExpenses: 80_000, monthlyRevenue: 0, monthlyGrowth: 0.2))
        #expect(zeroRevenue.growth == .never)
        let profitable = breakevens(Inputs(cash: 50_000, monthlyExpenses: 40_000, monthlyRevenue: 45_000, monthlyGrowth: 0.05))
        #expect(profitable.growth == .any)
        #expect(profitable.cash == .value(0))
        let rich = breakevens(Inputs(cash: 251_000, monthlyExpenses: 11_000, monthlyRevenue: 0, monthlyGrowth: 242, linear: true))
        #expect(rich.revenue == .any)
    }
}

@Suite("Balance curve")
struct BalanceCurveTests {
    @Test func aliveDipsToTheCushionAtProfitability() throws {
        let inputs = Inputs(cash: 400_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 5_000, linear: true)
        let curve = try #require(balanceCurve(inputs))
        #expect(curve.verdict == .alive)
        #expect(curve.marker == .init(t: 12, balance: 40_000, kind: .profitable))
        #expect(curve.points.first == .init(t: 0, balance: 400_000))
        #expect(close(curve.horizon, 12 * 1.35, within: 1e-9))
        #expect(close(curve.points.last?.t, curve.horizon, within: 1e-9))
    }

    @Test func deadEndsAtZero() throws {
        let inputs = Inputs(cash: 400_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 0.08)
        let curve = try #require(balanceCurve(inputs))
        let runway = try #require(project(inputs)?.runwayMonths)
        #expect(curve.marker?.kind == .broke)
        #expect(close(curve.points.last?.t, runway, within: 1e-9))
        #expect(close(curve.points.last?.balance, 0, within: 1e-3))
    }
}
