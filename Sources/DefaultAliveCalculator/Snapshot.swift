import AppKit
import DefaultAliveCore
import SwiftUI

/// `DefaultAliveCalculator --snapshot design/presets.json out.png` renders every preset in
/// light and dark into one contact sheet (rows = presets, columns = light | dark). It's the
/// app half of the design loop, the counterpart of design/index.html's gallery, which reads
/// the same presets file.
///
/// Rendered offscreen with cacheDisplay rather than screencapture: no Screen Recording
/// permission, no focus stealing, and no reads or writes of the user's saved input.
@MainActor
enum Snapshot {
    private struct PresetFile: Decodable {
        var presets: [Preset]
    }

    private struct Preset: Decodable {
        var name: String
        var input: RawInputs
        var units: Units?
        var linear: Bool?
        var taxes: TaxAssumptions?
        var assumptionsOpen: Bool?
    }

    static func run(presetsPath: String, outputPath: String) throws {
        _ = NSApplication.shared
        let data = try Data(contentsOf: URL(fileURLWithPath: presetsPath))
        let presets = try JSONDecoder().decode(PresetFile.self, from: data).presets
        let appearances = [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!]
        let tiles = presets.map { preset in appearances.map { render(preset, $0) } }

        let gap = 16
        let tileW = tiles.flatMap { $0 }.map(\.pixelsWide).max() ?? 0
        let tileH = tiles.flatMap { $0 }.map(\.pixelsHigh).max() ?? 0
        let sheetW = appearances.count * (tileW + gap) + gap
        let sheetH = presets.count * (tileH + gap) + gap
        let sheet = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: sheetW, pixelsHigh: sheetH, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
        NSColor(white: 0.5, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: sheetW, height: sheetH).fill()
        for (row, tilesInRow) in tiles.enumerated() {
            for (column, tile) in tilesInRow.enumerated() {
                // Bitmap origin is bottom-left; count rows down from the top, and pin each
                // tile to the top of its cell (tiles without a chart are shorter).
                let x = gap + column * (tileW + gap)
                let y = sheetH - gap - row * (tileH + gap) - tile.pixelsHigh
                tile.draw(in: NSRect(x: x, y: y, width: tile.pixelsWide, height: tile.pixelsHigh))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
    }

    private static func render(_ preset: Preset, _ appearance: NSAppearance) -> NSBitmapImageRep {
        let state = CalculatorState(input: preset.input, units: preset.units ?? .monthly, linear: preset.linear ?? false, taxes: preset.taxes)
        let form = CalculatorForm(model: CalculatorModel(state: state, chartShown: true, store: nil), assumptionsOpen: preset.assumptionsOpen ?? false)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: form)
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        // Always 2x. bitmapImageRepForCachingDisplay would follow the main screen, so the
        // same command gave 1x tiles whenever a non-Retina display was main, and the
        // gallery (which crops assuming 2x) showed them at half size.
        let scale = 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * scale, pixelsHigh: Int(host.bounds.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        // Draw at pixel size so Retina tiles aren't downscaled when composited.
        rep.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        return rep
    }
}
