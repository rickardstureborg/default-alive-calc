import AppKit
import DefaultAliveCore

/// The window's field editor (the text view AppKit lends whichever box is being edited).
///
/// It draws a grey thousands comma in a small gap after every third digit, so "1630000"
/// reads "1,630,000" from the first keystroke while the text itself stays raw: the cursor
/// steps over digits only and Backspace never has a comma to delete. It also drops "$",
/// "%" and "," as they're typed or pasted, since the box draws the unit and the commas.
///
/// Why not just put commas in the text: SwiftUI doesn't push a rewritten string into a
/// TextField while it's being edited, so regrouped commas only appeared after leaving the
/// box (`make selftest` showed the model holding "1,630,000" while the box showed
/// "1630000"), and real comma characters had to be deleted one by one.
///
/// @preconcurrency: NSTextStorageDelegate predates actor annotations; AppKit only calls it on
/// the main thread, during editing.
final class GroupingFieldEditor: NSTextView, @preconcurrency NSTextStorageDelegate {
    private var regrouping = false

    convenience init() {
        self.init(frame: .zero)
        isFieldEditor = true
        textStorage?.delegate = self
    }

    // MARK: Filtering

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let typed = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        let kept = normalizeField(typed)
        guard !kept.isEmpty || typed.isEmpty else { return }
        super.insertText(kept, replacementRange: replacementRange)
    }

    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return super.paste(sender) }
        insertText(text, replacementRange: selectedRange())
    }

    // MARK: Commas

    /// Re-kern after every change of characters, however it happened (typing, paste, or the
    /// box's text being replaced). Attributes may change here; characters may not.
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !regrouping else { return }
        regrouping = true
        defer { regrouping = false }
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.removeAttribute(.kern, range: full)
        for at in groupBreaks(textStorage.string) {
            textStorage.addAttribute(.kern, value: commaWidth(at: at - 1), range: NSRange(location: at - 1, length: 1))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let layoutManager, let storage = textStorage else { return }
        for at in groupBreaks(storage.string) where at < storage.length {
            // The comma sits in the kern gap just before the character at `at`.
            let glyph = layoutManager.glyphIndexForCharacter(at: at)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let location = layoutManager.location(forGlyphAt: glyph)
            let font = self.font(at: at - 1)
            let comma = NSAttributedString(string: ",", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
            let baseline = textContainerOrigin.y + line.minY + location.y
            comma.draw(at: NSPoint(x: textContainerOrigin.x + line.minX + location.x - comma.size().width,
                                   y: baseline - font.ascender))
        }
    }

    private func font(at index: Int) -> NSFont {
        textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? font ?? .systemFont(ofSize: NSFont.systemFontSize)
    }

    private func commaWidth(at index: Int) -> CGFloat {
        NSAttributedString(string: ",", attributes: [.font: font(at: index)]).size().width
    }
}
