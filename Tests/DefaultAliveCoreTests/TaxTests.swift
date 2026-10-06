import Foundation
import Testing
@testable import DefaultAliveCore

@Suite("Tax catalog")
struct TaxCatalogTests {
    private let places = TaxCatalog.places

    @Test func everyStateAndDCPlusTheCitiesThatChargeSomething() {
        let states = places.filter { !$0.local }
        #expect(states.count == 51)
        #expect(Set(states.map(\.state)).count == 51)
        #expect(places.count == 148)
        #expect(TaxCatalog.nothingOwed.count == 78)
        #expect(Set(places.map(\.id)).count == places.count)
    }

    @Test func entriesAreSane() {
        let stateCodes = Set(places.filter { !$0.local }.map(\.state))
        for p in places {
            #expect(stateCodes.contains(p.state), "\(p.id)")
            #expect((0...0.02).contains(p.rate), "\(p.id)")
            #expect((0...1).contains(p.share), "\(p.id)")
            #expect(p.perYear >= 0, "\(p.id)")
            #expect(!p.note.isEmpty, "\(p.id)")
            // An exclusion is measured on the revenue it taxes; placeRate relies on it.
            if let t = p.threshold, t.excess { #expect(t.on == .there, "\(p.id)") }
            // A threshold only means something for a receipts tax.
            if p.threshold != nil { #expect(p.rate > 0, "\(p.id)") }
        }
        #expect(TaxCatalog.defaultPlaces == ["DE"])
        #expect(TaxCatalog.defaultPlaces.allSatisfy { TaxCatalog.place($0) != nil })
    }

    @Test func groupedByStateWithTheStateFirst() {
        var seen: [String] = []
        for p in places where seen.last != p.state {
            #expect(!seen.contains(p.state), "\(p.state) split up")
            #expect(!p.local, "\(p.state) should lead with the state itself")
            seen.append(p.state)
        }
    }

    /// What the checklist's filter shows, and what "Add all" / "Remove all" act on: places
    /// where every word typed is part of the name or the state's name, or is the state's
    /// code. A state matched by name brings its cities; a city matched alone doesn't bring
    /// its state.
    @Test func filterMatchesNamesAndStates() {
        #expect(TaxCatalog.matching("").count == 148)
        #expect(TaxCatalog.matching("  ").count == 148)
        #expect(TaxCatalog.matching("seat").map(\.id) == ["WA-seattle"])
        #expect(TaxCatalog.matching("Tennessee").map(\.id)
            == ["TN", "TN-chattanooga", "TN-knoxville", "TN-memphis", "TN-nashville"])
        #expect(TaxCatalog.matching("tenn").count == 5)
        #expect(TaxCatalog.matching("tx").map(\.id) == ["TX"])
        #expect(TaxCatalog.matching("TX").map(\.id) == ["TX"])
        #expect(TaxCatalog.matching("seattle wa").map(\.id) == ["WA-seattle"])
        #expect(TaxCatalog.matching("kansas city").map(\.id) == ["KS-kansas-city", "MO-kansas-city"])
        #expect(TaxCatalog.matching("kansas city mo").map(\.id) == ["MO-kansas-city"])
        #expect(TaxCatalog.matching("oakland, ca").map(\.id) == ["CA-oakland"])
        #expect(TaxCatalog.matching("zzz").isEmpty)
    }

    /// Oakland taxes all the receipts of an Oakland office, with no small-business line.
    @Test func oaklandTaxesAllOfAnOaklandOffice() throws {
        let p = try #require(TaxCatalog.place("CA-oakland"))
        #expect(p.rate == 0.0036)
        #expect(p.share == 1)
        #expect(p.threshold == nil)
        #expect(TaxCatalog.place("nowhere") == nil)
    }
}

@Suite("Taxes")
struct TaxTests {
    private let base = Inputs(cash: 400_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 0.08)
    /// Oakland (a flat receipts tax), California (fixed fees only), Texas (a cliff).
    private let sample = TaxAssumptions(["CA": 0, "CA-oakland": 1, "TX": 0.1])

    private func place(_ id: String) -> TaxPlace { TaxCatalog.place(id)! }

    @Test func belowTexasThresholdOnlyOaklandReceiptsPlusFixedFees() {
        let t = withTaxes(base, sample)
        #expect(t.revenueRate == 0.0036)
        #expect(t.fixedMonthly == 889.0 / 12)
        #expect(abs(t.inputs.monthlyRevenue - 20_000 * (1 - 0.0036)) < 1e-9)
        #expect(t.inputs.monthlyExpenses == 80_000 + 889.0 / 12)
        #expect(t.inputs.monthlyGrowth == 0.08)
    }

    // $250k/mo is $3M/yr, over Texas's $2.65M no-tax-due line (a cliff on total revenue).
    @Test func overTexasThresholdAddsTexasEZ() {
        var big = base
        big.monthlyRevenue = 250_000
        #expect(withTaxes(big, sample).revenueRate == 0.0036 + 0.00331 * 0.1)
        big.monthlyRevenue = 2_650_000.0 / 12
        #expect(withTaxes(big, sample).revenueRate == 0.0036, "at the line, nothing is due")
    }

    // Ohio's CAT excludes the first $6M of Ohio receipts: $10M/yr there pays on $4M.
    @Test func exclusionTaxesOnlyTheExcess() {
        let ohio = place("OH")
        #expect(abs(placeRate(ohio, share: 1, annual: 10_000_000) - 0.0026 * 0.4) < 1e-15)
        #expect(placeRate(ohio, share: 1, annual: 6_000_000) == 0)
        #expect(placeRate(ohio, share: 0.5, annual: 10_000_000) == 0, "only $5M counted there")
    }

    // Arlington's BPOL: past $100k at the Arlington office, the rate applies to all of it.
    @Test func cliffOnRevenueThereTaxesAllOfIt() {
        let arlington = place("VA-arlington-county")
        #expect(placeRate(arlington, share: 1, annual: 150_000) == 0.0036)
        #expect(placeRate(arlington, share: 1, annual: 90_000) == 0)
        #expect(placeRate(arlington, share: 0.5, annual: 150_000) == 0, "$75k there is under the line")
        #expect(placeRate(place("CA"), share: 1, annual: 1e9) == 0, "no receipts tax")
        #expect(placeRate(place("CA-oakland"), share: 0.5, annual: 0) == 0.0036 * 0.5)
    }

    @Test func unknownPlacesAndNoPlacesCostNothing() {
        let t = withTaxes(base, TaxAssumptions(["gone": 1]))
        #expect(t.revenueRate == 0 && t.fixedMonthly == 0)
        #expect(withTaxes(base, TaxAssumptions([:])).inputs == base)
    }

    @Test func linearGrowthIsTaxedLikeRevenue() {
        let t = withTaxes(Inputs(cash: 400_000, monthlyExpenses: 80_000, monthlyRevenue: 20_000, monthlyGrowth: 5_000, linear: true), sample)
        #expect(abs(t.inputs.monthlyGrowth - 5_000 * (1 - 0.0036)) < 1e-9)
    }

    /// Gross breakevens, taxed again, land exactly on capital needed == cash.
    @Test func grossBreakevensRoundTrip() throws {
        let t = withTaxes(base, sample)
        let b = t.gross(breakevens(t.inputs))
        guard case let .value(revenue) = b.revenue, case let .value(expenses) = b.expenses else {
            Issue.record("expected values, got \(b)")
            return
        }
        var r = base; r.monthlyRevenue = revenue
        #expect(abs((project(withTaxes(r, sample).inputs)?.capitalNeeded ?? 0) - base.cash) < 1e-3)
        var e = base; e.monthlyExpenses = expenses
        #expect(abs((project(withTaxes(e, sample).inputs)?.capitalNeeded ?? 0) - base.cash) < 1e-3)
    }

    /// Same strings as model.test.mjs: the mock shows these too.
    @Test func summaries() {
        #expect(placeSummary(place("CA-oakland")) == "0.36% of revenue there + $64/yr")
        #expect(placeSummary(place("TX")) == "0.331% of revenue there, once revenue tops $2.65M/yr")
        #expect(placeSummary(place("DE")) == "0.3983% of revenue there above $1.2M/yr + $450/yr")
        #expect(placeSummary(place("VA-arlington-county")) == "0.36% of revenue there, once it tops $100k/yr + $50/yr")
        #expect(placeSummary(place("MO")) == "$20/yr")
        #expect(placeSummary(place("AL")) == "$0")
        #expect(placeSummary(place("DE"), short: true) == "0.3983% + $450/yr")
        #expect(placeSummary(place("TX"), short: true) == "0.331%")
    }

    @Test func ratesKeepTheirDigits() {
        #expect(formatRate(0.003983) == "0.3983%")
        #expect(formatRate(0.00331) == "0.331%")
        #expect(formatRate(0.0125) == "1.25%")
        #expect(formatRate(0.0000052, digits: 2) == "0.00052%")
        #expect(formatRate(0.003983, digits: 2) == "0.4%")
        #expect(formatRate(0) == "0%")
    }

    @Test func sharesArePercentagesUpToAHundred() {
        #expect(shareValue("0.5") == 0.005)
        #expect(shareValue("100") == 1)
        #expect(shareValue("0") == 0)
        #expect(shareValue("10%") == 0.1)
        #expect(shareValue("150") == nil)
        #expect(shareValue("-1") == nil)
        #expect(shareValue("") == nil)
        #expect(shareValue("abc") == nil)
    }
}

@Suite("Tax places in the form")
struct TaxStateTests {
    private let now = Date(timeIntervalSince1970: 1_768_000_000)
    private func filled() -> CalculatorState {
        CalculatorState(input: RawInputs(cash: "$400k", expenses: "80k", revenue: "20k", growth: "8%"))
    }

    @Test func startsWithDelawareAtItsDefaultShare() {
        var s = filled()
        #expect(s.taxPlaces == ["DE"])
        #expect(s.shareText("DE") == "0.3")
        #expect(s.taxAssumptions == nil, "off until ticked")
        #expect(s.taxSummary == "")
        s.taxesOn = true
        #expect(s.taxAssumptions == TaxAssumptions(["DE": 0.003]))
        #expect(s.taxSummary == "≈ 0% + $450/yr")
    }

    @Test func removingKeepsTheShareForWhenItComesBack() {
        var s = filled()
        s.setTaxPlace("TX", included: true)
        s.taxShares["TX"] = "25"
        s.setTaxPlace("TX", included: false)
        #expect(s.taxPlaces == ["DE"])
        s.setTaxPlace("TX", included: true)
        #expect(s.shareText("TX") == "25")
    }

    @Test func placesStayInCatalogOrder() {
        var s = filled()
        s.setTaxPlace("WA-seattle", included: true)
        s.setTaxPlace("AL", included: true)
        s.setTaxPlace("AL", included: true)
        #expect(s.taxPlaces == ["AL", "DE", "WA-seattle"])
        s.taxPlaces = ["TX", "gone", "DE", "TX"]
        #expect(s.taxPlaces == ["DE", "TX"])
    }

    @Test func addAllAndRemoveAllActOnWhatTheFilterShows() {
        var s = filled()
        s.setTaxPlaces(TaxCatalog.matching("virginia").map(\.id), included: true)
        #expect(s.taxPlaces.count == 1 + 14, "Virginia and its 7 localities, West Virginia and its 5 cities")
        s.setTaxPlaces(TaxCatalog.matching("").map(\.id), included: true)
        #expect(s.taxPlaces == TaxCatalog.places.map(\.id))
        s.setTaxPlaces(TaxCatalog.matching("").map(\.id), included: false)
        #expect(s.taxPlaces.isEmpty)
        s.taxesOn = true
        #expect(s.taxSummary == "≈ 0% + $0/yr")
    }

    @Test func aBadShareTurnsTaxesOffUntilFixed() {
        var s = filled()
        s.taxesOn = true
        s.setTaxPlace("CA-oakland", included: true)
        #expect(s.readout(now: now).hints.cash == "≥ $665.1k")
        #expect(s.taxSummary == "≈ 0.36% + $514/yr")
        let off = { var o = s; o.taxesOn = false; return o.readout(now: now) }()
        s.taxShares["CA-oakland"] = "abc"
        #expect(s.isInvalidShare("CA-oakland"))
        #expect(s.taxAssumptions == nil)
        #expect(s.readout(now: now) == off)
        s.taxShares["CA-oakland"] = "150"
        #expect(s.isInvalidShare("CA-oakland"))
        // California has no receipts tax, so no share box, and its share never matters.
        s.taxShares["CA-oakland"] = "100"
        s.setTaxPlace("CA", included: true)
        s.taxShares["CA"] = "abc"
        #expect(!s.isInvalidShare("CA"))
        #expect(s.taxAssumptions != nil)
    }

    @Test func presetTaxesSelectExactlyThosePlaces() {
        let s = CalculatorState(input: RawInputs(cash: "1", expenses: "1", revenue: "1", growth: "1"),
                                taxes: TaxAssumptions(["TX": 0.1, "OH": 0.035]))
        #expect(s.taxesOn)
        #expect(s.taxPlaces == ["OH", "TX"])
        #expect(s.shareText("TX") == "10")
        #expect(s.shareText("OH") == "3.5")
    }
}

@Suite("Growth from the chart")
struct GrowthFromChartTests {
    /// The chart plots after-tax numbers; $ growth read off it is net of receipts taxes,
    /// so it's grossed back up for the box. % growth is unchanged by a flat cut.
    @Test func dollarGrowthIsGrossedUpUnderTaxes() {
        var s = CalculatorState(input: RawInputs(cash: "400k", expenses: "80k", revenue: "20k", growth: "8"))
        #expect(s.growthFromChart(0.1) == 0.1)
        s.taxesOn = true
        s.setTaxPlace("CA-oakland", included: true)
        #expect(s.growthFromChart(0.1) == 0.1)
        s.toggleGrowthKind()
        #expect(abs(s.growthFromChart(5_000) - 5_000 / (1 - 0.0036)) < 1e-9)
    }
}
