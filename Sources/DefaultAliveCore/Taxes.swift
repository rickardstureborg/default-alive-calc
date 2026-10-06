import Foundation

// Only taxes that cost money before profitability can change the verdict: default alive
// asks whether you reach breakeven, and at breakeven profit is zero, so income taxes
// (federal 21%, California corporate net income 8.84%) are all zero on the way there.
// What's left for an Oakland company
// incorporated in Delaware and registered in WA/DE/CA, from oaklandca.gov,
// dor.wa.gov, corp.delaware.gov and ftb.ca.gov (checked Oct 2026):
public enum TaxRates {
    /// Oakland business tax, Class F (professional services), 2026: 0.36% of gross
    /// receipts, with no small-business exemption.
    public static let oaklandReceipts = 0.0036
    /// Washington B&O tax on retailing (SaaS), 2026: a small business credit clears it
    /// up to about $140k a year of Washington receipts; above that, 0.471% of them.
    public static let washingtonBO = 0.00471
    public static let washingtonCredit = 140_000.0
    /// Delaware franchise tax minimum under the assumed par value capital method ($400)
    /// plus the $50 annual report. (The authorized shares method can bill far more.)
    public static let delawarePerYear = 450.0
}

/// The two business-specific inputs: what fraction of revenue is sourced to each place.
public struct TaxAssumptions: Equatable, Sendable, Codable {
    public var oaklandShare: Double
    public var washingtonShare: Double

    public init(oaklandShare: Double, washingtonShare: Double) {
        self.oaklandShare = oaklandShare
        self.washingtonShare = washingtonShare
    }
}

public struct Taxed: Sendable {
    /// Revenue net of receipts taxes, fixed taxes added to expenses.
    public var inputs: Inputs
    public var revenueRate: Double
    public var fixedMonthly: Double
    let linear: Bool

    /// Breakevens computed on `inputs`, turned back into the numbers you'd type.
    public func gross(_ b: Breakevens) -> Breakevens {
        let keep = 1 - revenueRate
        func back(_ t: Threshold, _ f: (Double) -> Double) -> Threshold {
            if case let .value(v) = t { .value(f(v)) } else { t }
        }
        return Breakevens(
            cash: b.cash,
            expenses: back(b.expenses) { max(0, $0 - fixedMonthly) },
            revenue: back(b.revenue) { $0 / keep },
            // A % growth rate is unchanged by a flat cut; $ growth adds taxed revenue.
            growth: linear ? back(b.growth) { $0 / keep } : b.growth)
    }
}

/// Washington switches on from current revenue only; a forecast that crosses its credit
/// part way is ignored (it's worth ~0.05% of revenue).
public func withTaxes(_ inputs: Inputs, _ a: TaxAssumptions) -> Taxed {
    let overWashington = inputs.monthlyRevenue * 12 * a.washingtonShare > TaxRates.washingtonCredit
    let revenueRate = TaxRates.oaklandReceipts * a.oaklandShare + (overWashington ? TaxRates.washingtonBO * a.washingtonShare : 0)
    let fixedMonthly = TaxRates.delawarePerYear / 12
    let keep = 1 - revenueRate
    var after = inputs
    after.monthlyRevenue *= keep
    if inputs.linear { after.monthlyGrowth *= keep }
    after.monthlyExpenses += fixedMonthly
    return Taxed(inputs: after, revenueRate: revenueRate, fixedMonthly: fixedMonthly, linear: inputs.linear)
}
