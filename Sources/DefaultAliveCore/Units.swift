import Foundation

// The model runs in months; each flow field can be typed per week, month or year.
// Weeks per month is TLB's 365.2425/7/12. % growth compounds per period, so 8%/mo is
// 1.79%/wk and 152%/yr (not 2% and 96%). $ growth means MRR rises by that much each growth
// period: "+$10k of MRR a month" is +$120k of MRR a year. It's linear in the growth period,
// not squared (an earlier version scaled it by period², so +$50/wk read as +$136k/yr), and
// always measured on MRR, whatever unit the Revenue box is in: when it was measured on the
// Revenue box's figure, clicking Revenue's unit had to rewrite the growth box too, and each
// unit toggle must only change its own box.

/// The period a flow field is typed in.
public enum Period: String, CaseIterable, Codable, Sendable {
    case week, month, year

    public var months: Double {
        switch self {
        case .week: 12 * 7 / 365.2425
        case .month: 1
        case .year: 12
        }
    }

    /// Clicking the unit cycles week → month → year → week.
    public var next: Period {
        switch self {
        case .week: .month
        case .month: .year
        case .year: .week
        }
    }
}

public struct Units: Equatable, Codable, Sendable {
    public var expenses: Period
    public var revenue: Period
    public var growth: Period

    public init(expenses: Period = .month, revenue: Period = .month, growth: Period = .month) {
        self.expenses = expenses
        self.revenue = revenue
        self.growth = growth
    }

    public static let monthly = Units()
}

public func amountToUnit(_ monthly: Double, _ unit: Period) -> Double { monthly * unit.months }
public func amountFromUnit(_ perUnit: Double, _ unit: Period) -> Double { perUnit / unit.months }
public func growthToUnit(_ monthly: Double, _ unit: Period) -> Double { expm1(log1p(monthly) * unit.months) }
public func growthFromUnit(_ perUnit: Double, _ unit: Period) -> Double { expm1(log1p(perUnit) / unit.months) }
public func linearToUnit(_ monthly: Double, _ unit: Period) -> Double { monthly * unit.months }
public func linearFromUnit(_ perUnit: Double, _ unit: Period) -> Double { perUnit / unit.months }
