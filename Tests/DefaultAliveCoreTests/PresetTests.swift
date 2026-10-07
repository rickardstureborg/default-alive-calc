import Foundation
import Testing
@testable import DefaultAliveCore

/// design/presets.json is the spec for the result text and hints, shared with
/// design/model.test.mjs, so the browser preview and the app can't quietly disagree.
struct PresetFile: Decodable {
    struct Preset: Decodable {
        var name: String
        var input: RawInputs
        var units: Units?
        var linear: Bool?
        var taxes: TaxAssumptions?
        var expect: Readout
        /// The line under $ growth. A sibling of `expect` because that's compared whole against `Readout`.
        var note: String?

        var state: CalculatorState {
            CalculatorState(input: input, units: units ?? .monthly, linear: linear ?? false, taxes: taxes)
        }
    }
    var now: String
    var presets: [Preset]

    static func load() throws -> PresetFile {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("design/presets.json")
        return try JSONDecoder().decode(PresetFile.self, from: Data(contentsOf: url))
    }

    /// Local midnight, the same instant `new Date(y, m - 1, d)` gives in model.test.mjs.
    var nowDate: Date {
        get throws {
            let parts = now.split(separator: "-").compactMap { Int($0) }
            return try #require(Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])))
        }
    }
}

@Suite("Presets")
struct PresetTests {
    @Test func everyPresetReadsAsSpecified() throws {
        let file = try PresetFile.load()
        #expect(!file.presets.isEmpty)
        let now = try file.nowDate
        for p in file.presets {
            let r = readout(p.input, units: p.units ?? .monthly, linear: p.linear ?? false, taxes: p.taxes, now: now)
            #expect(r == p.expect, "preset \(p.name)")
        }
    }

    /// The form state built from a preset reads the same as the raw strings do.
    @Test func calculatorStateMatchesRawReadout() throws {
        let file = try PresetFile.load()
        let now = try file.nowDate
        for p in file.presets {
            #expect(p.state.readout(now: now) == p.expect, "preset \(p.name)")
        }
    }

    /// Every $ growth preset has a `note`, and % presets have none, the same as the form shows.
    @Test func growthNotesReadAsSpecified() throws {
        let file = try PresetFile.load()
        #expect(file.presets.contains { $0.note != nil })
        for p in file.presets {
            let units = p.units ?? .monthly
            if let note = p.note {
                #expect(growthNote(p.input.growth, unit: units.growth, revenueUnit: units.revenue) == note, "preset \(p.name)")
            }
            #expect(p.state.growthNote == p.note, "preset \(p.name)")
        }
    }

    @Test func fieldRanges() {
        #expect(amountValue("80k") == 80_000)
        #expect(amountValue("0") == 0)
        #expect(amountValue("-5") == nil)
        #expect(amountValue("") == nil)
        #expect(growthValue("-99") == -0.99)
        #expect(growthValue("-100") == nil)
        #expect(growthValue("x") == nil)
    }
}
