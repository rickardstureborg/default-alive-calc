import DefaultAliveCore
import Foundation
import Observation

/// The form's state plus whether the chart is open, persisted to UserDefaults on every
/// change. That's the app's only stored state: the typed text and unit of each box (both
/// growth kinds), which growth kind is showing, the tax checkbox, the tax places and the
/// shares typed for them, and the chart toggle. Whether the tax assumptions are open is not stored. Each box's exact
/// value behind a converted display lives in memory only, so after a relaunch a converted
/// box computes from its displayed text (a rounding-level difference at most).
@MainActor
@Observable
final class CalculatorModel {
    var state: CalculatorState {
        didSet { save() }
    }
    var chartShown: Bool {
        didSet { store?.set(chartShown, forKey: "chartShown") }
    }

    /// nil for snapshots, which must never read or write the user's input.
    @ObservationIgnored private let store: UserDefaults?

    init(state: CalculatorState, chartShown: Bool, store: UserDefaults?) {
        self.state = state
        self.chartShown = chartShown
        self.store = store
    }

    static func load(from d: UserDefaults) -> CalculatorModel {
        // v1 stored the only growth box as "growth"; it was always a percentage.
        if let old = d.string(forKey: "growth") {
            if d.string(forKey: "growthPercent") == nil { d.set(old, forKey: "growthPercent") }
            d.removeObject(forKey: "growth")
        }
        func field(_ key: String) -> Field {
            Field(text: d.string(forKey: key) ?? "", unit: Period(rawValue: d.string(forKey: key + "Unit") ?? "") ?? .month)
        }
        var s = CalculatorState()
        s.cash = Field(text: d.string(forKey: "cash") ?? "")
        s.expenses = field("expenses")
        s.revenue = field("revenue")
        s.growthPercent = field("growthPercent")
        s.growthDollar = field("growthDollar")
        s.linear = d.bool(forKey: "growthLinear")
        s.taxesOn = d.bool(forKey: "taxesOn")
        if let places = d.stringArray(forKey: "taxPlaces") { s.taxPlaces = places }
        s.taxShares = d.dictionary(forKey: "taxShares") as? [String: String] ?? [:]
        return CalculatorModel(state: s, chartShown: d.object(forKey: "chartShown") as? Bool ?? true, store: d)
    }

    private func save() {
        guard let d = store else { return }
        d.set(state.cash.text, forKey: "cash")
        for (key, f) in [("expenses", state.expenses), ("revenue", state.revenue),
                         ("growthPercent", state.growthPercent), ("growthDollar", state.growthDollar)] {
            d.set(f.text, forKey: key)
            d.set(f.unit.rawValue, forKey: key + "Unit")
        }
        d.set(state.linear, forKey: "growthLinear")
        d.set(state.taxesOn, forKey: "taxesOn")
        d.set(state.taxPlaces, forKey: "taxPlaces")
        d.set(state.taxShares, forKey: "taxShares")
    }
}
