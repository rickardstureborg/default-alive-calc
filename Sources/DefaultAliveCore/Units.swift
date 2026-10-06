import Foundation

// The model runs in months; each flow field can be typed per week, month or year.
// Weeks per month is TLB's 365.2425/7/12. % growth compounds per period, so 8%/mo is
// 1.79%/wk and 152%/yr (not 2% and 96%). $ growth means the per-period revenue figure
// rises by that much each period ("+$10k MRR a month"), so it scales with period².

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
public func linearToUnit(_ monthly: Double, _ unit: Period) -> Double { monthly * unit.months * unit.months }
public func linearFromUnit(_ perUnit: Double, _ unit: Period) -> Double { perUnit / (unit.months * unit.months) }
