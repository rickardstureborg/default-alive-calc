import Foundation

// Only taxes that cost money before profitability can change the verdict: default alive
// asks whether you reach breakeven, and at breakeven profit is zero, so income taxes are
// zero all the way there. What's left are receipts taxes and fixed yearly amounts, per
// state and city, in TaxPlaces.json: built from docs/tax-research/ (one agent per state,
// official sources, Oct 2026) by places.mjs there, compiled in via Package.swift's
// .embedInCode, and read by the browser mock too. Re-check yearly (places.mjs says how).

/// One state or city on the checklist.
public struct TaxPlace: Decodable, Sendable, Equatable, Identifiable {
    public struct Threshold: Decodable, Sendable, Equatable {
        public enum Basis: String, Decodable, Sendable { case total, there }
        /// Revenue a year at or under which nothing is owed.
        public let perYear: Double
        /// Measured on total revenue, or on the revenue counted to this place.
        public let on: Basis
        /// Only the revenue above the threshold is taxed (an exclusion), rather than all of
        /// it once past (a cliff).
        public let excess: Bool
    }

    /// "CA" for a state, "CA-oakland" for a city.
    public let id: String
    public let name: String
    public let state: String
    public let local: Bool
    /// Receipts tax as a fraction of the revenue counted here; 0 if none.
    public let rate: Double
    /// Suggested share of revenue counted here: the place's share of US population for a
    /// tax sourced to customers, 1 for one sourced to your office.
    public let share: Double
    public let threshold: Threshold?
    /// Fixed amounts owed every year regardless of revenue (minimum taxes, report fees).
    public let perYear: Double
    /// The assumption in a sentence, shown on hover.
    public let note: String
}

public enum TaxCatalog {
    private struct File: Decodable {
        var checked: String
        var places: [TaxPlace]
        var nothingOwed: [String]
    }

    private static let file: File = {
        // The file ships inside the binary; a decode failure is a build mistake, caught by
        // TaxCatalogTests before it could reach the app.
        try! JSONDecoder().decode(File.self, from: Data(PackageResources.TaxPlaces_json))
    }()

    /// Every place, states first within each state, states alphabetical.
    public static var places: [TaxPlace] { file.places }
    /// Cities checked that owe nothing before profit (not on the checklist).
    public static var nothingOwed: [String] { file.nothingOwed }
    public static var checked: String { file.checked }

    private static let byID = Dictionary(uniqueKeysWithValues: file.places.map { ($0.id, $0) })
    private static let stateNames = Dictionary(file.places.filter { !$0.local }.map { ($0.state, $0.name) },
                                               uniquingKeysWith: { first, _ in first })

    public static func place(_ id: String) -> TaxPlace? { byID[id] }

    /// What the checklist's filter shows, and what "Add all" / "Remove all" act on: places
    /// where every word typed is part of the name or the state's name, or is the state's
    /// code ("kansas city mo", "tenn", "tx").
    public static func matching(_ query: String) -> [TaxPlace] {
        let words = query.lowercased().split { $0.isWhitespace || $0 == "," }.map(String.init)
        return places.filter { p in
            let name = p.name.lowercased(), state = (stateNames[p.state] ?? "").lowercased(), code = p.state.lowercased()
            return words.allSatisfy { name.contains($0) || state.contains($0) || code == $0 }
        }
    }

    /// Most venture-backed startups are Delaware corporations; every other place is the
    /// user's to add.
    public static let defaultPlaces = ["DE"]
}

/// The share of revenue a place's receipts tax takes at `annual` revenue: rate × share,
/// or nothing at or under its threshold, or only the part above it for an exclusion.
/// Thresholds are judged on current revenue only; a forecast that crosses one mid-way is
/// ignored (Texas's is worth ~0.03% of revenue).
public func placeRate(_ place: TaxPlace, share: Double, annual: Double) -> Double {
    guard place.rate > 0 else { return 0 }
    guard let t = place.threshold else { return place.rate * share }
    let there = annual * share
    guard (t.on == .total ? annual : there) > t.perYear else { return 0 }
    return t.excess ? place.rate * share * (1 - t.perYear / there) : place.rate * share
}

/// "0.331% of revenue there, once revenue tops $2.65M/yr": what a place costs, in a line.
/// `short` drops the threshold, for the checklist.
public func placeSummary(_ place: TaxPlace, short: Bool = false) -> String {
    var parts: [String] = []
    if place.rate > 0 {
        var when = ""
        if let t = place.threshold, !short {
            let amount = formatMoneyBound(t.perYear, roundUp: true)
            when = t.excess ? " above \(amount)/yr" : t.on == .total ? ", once revenue tops \(amount)/yr" : ", once it tops \(amount)/yr"
        }
        parts.append(short ? formatRate(place.rate) : "\(formatRate(place.rate)) of revenue there\(when)")
    }
    if place.perYear > 0 { parts.append("\(formatMoney(place.perYear))/yr") }
    return parts.isEmpty ? "$0" : parts.joined(separator: " + ")
}

/// 0.023 → "2.3", how a share is shown in its box.
func percentText(_ fraction: Double) -> String { trimZeros(String(format: "%.4f", fraction * 100)) }

/// A typed share of revenue: a percentage from 0 to 100, as a fraction.
public func shareValue(_ text: String) -> Double? {
    guard let v = parsePercent(text), (0...1).contains(v) else { return nil }
    return v
}

/// The places you're in and the share of revenue counted to each. Decodes from a plain
/// {"CA-oakland": 1} object, as in presets.json.
public struct TaxAssumptions: Equatable, Sendable, Codable {
    public var shares: [String: Double]

    public init(_ shares: [String: Double]) {
        self.shares = shares
    }

    public init(from decoder: Decoder) throws {
        shares = try decoder.singleValueContainer().decode([String: Double].self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(shares)
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

public func withTaxes(_ inputs: Inputs, _ a: TaxAssumptions) -> Taxed {
    let annual = inputs.monthlyRevenue * 12
    var revenueRate = 0.0, perYear = 0.0
    // Catalog order, not the dictionary's, so the sum (and its last bit) matches model.js.
    for place in TaxCatalog.places {
        guard let share = a.shares[place.id] else { continue }
        revenueRate += placeRate(place, share: share, annual: annual)
        perYear += place.perYear
    }
    let fixedMonthly = perYear / 12
    let keep = 1 - revenueRate
    var after = inputs
    after.monthlyRevenue *= keep
    if inputs.linear { after.monthlyGrowth *= keep }
    after.monthlyExpenses += fixedMonthly
    return Taxed(inputs: after, revenueRate: revenueRate, fixedMonthly: fixedMonthly, linear: inputs.linear)
}
