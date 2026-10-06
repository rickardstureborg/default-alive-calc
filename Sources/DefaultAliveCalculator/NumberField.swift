import AppKit
import DefaultAliveCore
import SwiftUI

/// A keyboard-driven focus move for the four boxes. `serial` makes each request distinct, so
/// asking for the same box twice still re-places the cursor.
struct FocusRequest: Equatable {
    /// nil: take the cursor out of every box.
    var row: Row?
    /// Select the whole box (Tab/Return forward) or park the cursor at the end.
    var selectAll: Bool
    var serial: Int
}

/// One of the four boxes: an AppKit text field rather than SwiftUI's TextField, because
/// SwiftUI's uses a private field editor (_SystemTextFieldFieldEditor) and never asks the
/// window for one, so GroupingFieldEditor's drawn commas and keystroke filtering never ran
/// in it (`make selftest` reported the class). Owning the field also makes focus and cursor
/// placement synchronous: we call makeFirstResponder ourselves and select right after.
struct NumberField: NSViewRepresentable {
    @Binding var text: String
    let row: Row
    let prompt: String
    let invalid: Bool
    @Binding var focus: Row?
    let request: FocusRequest?

    func makeNSView(context: Context) -> NumberTextField {
        let field = NumberTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: Style.fieldSize, weight: .regular)
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NumberTextField, context: Context) {
        context.coordinator.parent = self
        field.onFocus = { [weak coordinator = context.coordinator] in coordinator?.parent.focus = row }
        field.onBlur = { [weak coordinator = context.coordinator] in
            if coordinator?.parent.focus == row { coordinator?.parent.focus = nil }
        }
        field.placeholderString = prompt
        field.textColor = invalid ? NSColor(Style.dead) : .textColor
        // Model changes (clear, unit cycle, Return's compaction) show at once, even mid-edit.
        if field.stringValue != text {
            if let editor = field.currentEditor() {
                let caret = min(editor.selectedRange.location, (text as NSString).length)
                editor.string = text
                editor.selectedRange = NSRange(location: caret, length: 0)
            } else {
                field.stringValue = text
            }
        }
        if let request, request.serial != context.coordinator.handled {
            context.coordinator.handled = request.serial
            DispatchQueue.main.async { apply(request, to: field) }
        }
    }

    private func apply(_ request: FocusRequest, to field: NumberTextField) {
        guard let window = field.window else { return }
        if request.row == row {
            if field.currentEditor() == nil { window.makeFirstResponder(field) }
            guard let editor = field.currentEditor() else { return }
            let end = (editor.string as NSString).length
            editor.selectedRange = request.selectAll ? NSRange(location: 0, length: end) : NSRange(location: end, length: 0)
        } else if request.row == nil, field.currentEditor() != nil {
            window.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumberField
        var handled = -1

        init(parent: NumberField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

final class NumberTextField: NSTextField {
    var onFocus: (() -> Void)?
    var onBlur: (() -> Void)?

    override class var cellClass: AnyClass? {
        get { NumberFieldCell.self }
        set {}
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus?() }
        return became
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onBlur?()
    }
}

/// While editing, GroupingFieldEditor draws the commas. Otherwise the cell does, the same
/// way: grey commas set into a copy of the text for drawing only.
final class NumberFieldCell: NSTextFieldCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let text = stringValue
        guard !text.isEmpty, (controlView as? NSTextField)?.currentEditor() == nil else {
            return super.drawInterior(withFrame: cellFrame, in: controlView)
        }
        let font = self.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let ink: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor ?? .textColor, .paragraphStyle: paragraph]
        var comma = ink
        comma[.foregroundColor] = NSColor.secondaryLabelColor
        let shown = NSMutableAttributedString()
        let units = Array(text.utf16)
        var from = 0
        for at in groupBreaks(text) + [units.count] {
            shown.append(NSAttributedString(string: String(decoding: units[from..<at], as: UTF16.self), attributes: ink))
            if at < units.count { shown.append(NSAttributedString(string: ",", attributes: comma)) }
            from = at
        }
        shown.draw(with: titleRect(forBounds: cellFrame), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
