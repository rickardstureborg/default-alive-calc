import Foundation
import Testing
@testable import DefaultAliveCore

/// design/presets.json is the spec for the result text, shared with design/model.test.mjs,
/// so the browser preview and the app can't quietly disagree.
struct PresetFile: Decodable {
    struct Preset: Decodable {
        var name: String
        var input: RawInputs
        var expect: Readout
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
        for preset in file.presets {
            #expect(readout(preset.input, now: now) == preset.expect, "preset \(preset.name)")
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
