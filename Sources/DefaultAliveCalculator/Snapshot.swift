import AppKit
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
    private struct Preset: Decodable {
        var name: String
        var cash, expenses, revenue, growth: String
    }

    static func run(presetsPath: String, outputPath: String) throws {
        _ = NSApplication.shared
        let presets = try JSONDecoder().decode([Preset].self, from: Data(contentsOf: URL(fileURLWithPath: presetsPath)))
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
                // Bitmap origin is bottom-left; count rows down from the top.
                let x = gap + column * (tileW + gap)
                let y = sheetH - (row + 1) * (tileH + gap)
                tile.draw(in: NSRect(x: x, y: y, width: tile.pixelsWide, height: tile.pixelsHigh))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
    }

    private static func render(_ preset: Preset, _ appearance: NSAppearance) -> NSBitmapImageRep {
        let form = CalculatorForm(
            cash: .constant(preset.cash), expenses: .constant(preset.expenses),
            revenue: .constant(preset.revenue), growth: .constant(preset.growth))
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: form)
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        // Draw at pixel size so Retina tiles aren't downscaled when composited.
        rep.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        return rep
    }
}
