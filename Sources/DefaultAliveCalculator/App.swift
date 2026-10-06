import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var keyMonitor: Any?
    private let fieldEditor = GroupingFieldEditor()

    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 2 < args.count {
            do {
                try Snapshot.run(presetsPath: args[i + 1], outputPath: args[i + 2])
            } catch {
                FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
                exit(1)
            }
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        let args = CommandLine.arguments
        let selfTestOutput = args.firstIndex(of: "--selftest").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        let model = selfTestOutput == nil
            ? CalculatorModel.load(from: .standard)
            : CalculatorModel(state: SelfTest.state, chartShown: false, store: nil)
        let controller = NSHostingController(rootView: CalculatorForm(model: model))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Default Alive Calculator"
        // The last input is the only thing this app remembers: no restored windows, no
        // saved frame. Opens centered every time.
        window.isRestorable = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate()

        // A local monitor runs before the field editor sees the key, which is what lets
        // Esc / C / keypad Clear clear everything even while a box has the cursor. Plain C
        // is safe to steal because no box accepts letters other than k/m/b, and ⌘C (copy)
        // still passes. ⌘⌫ clears everything only when no box has the cursor; inside a box
        // it passes through to its normal meaning, delete back to the start of the box.
        //
        // Tab and Return both move to the next box and Shift reverses, wrapping at the
        // ends. Handled here rather than by AppKit's key-view loop because that loop also
        // stops on the unit/kind buttons whenever System Settings' keyboard navigation is
        // on; this way only the four boxes are ever stops.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.window === self?.window else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let esc = event.keyCode == 53 && mods.isEmpty
            let c = event.charactersIgnoringModifiers?.lowercased() == "c" && mods.subtracting(.shift).isEmpty
            // 71: the keypad's Clear key (Apple extended / Macally keyboards).
            let keypadClear = event.keyCode == 71
            let inBox = event.window?.firstResponder is NSTextView
            let cmdDelete = event.keyCode == 51 && mods == .command && !inBox
            if esc || c || keypadClear || cmdDelete {
                NotificationCenter.default.post(name: .clearInputs, object: nil)
                return nil
            }
            // 48 Tab, 36 Return, 76 keypad Enter.
            if [48, 36, 76].contains(event.keyCode), mods.subtracting(.shift).isEmpty {
                // Return also compacts an expression in the box it leaves; Tab leaves it as typed.
                NotificationCenter.default.post(name: .moveFocus, object: nil,
                                                userInfo: ["forward": !mods.contains(.shift), "commit": event.keyCode != 48])
                return nil
            }
            // 125 Down, 126 Up: the box below / above, no wrapping, cursor at the end. With a
            // modifier (⇧ ⌥ ⌘) they keep their text-selection meaning.
            if [125, 126].contains(event.keyCode), mods.isEmpty {
                NotificationCenter.default.post(name: .moveFocus, object: nil, userInfo: ["arrow": true, "forward": event.keyCode == 125])
                return nil
            }
            return event
        }

        if let selfTestOutput { SelfTest.run(window: window, model: model, output: selfTestOutput) }
    }

    /// Every box edits through the comma-drawing field editor.
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? { fieldEditor }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc private func clearInputs(_ sender: Any?) {
        NotificationCenter.default.post(name: .clearInputs, object: nil)
    }

    // Without a main menu, ⌘Q and the text-editing shortcuts (⌘C/⌘V/⌘A/⌘Z) do nothing.
    private func makeMainMenu() -> NSMenu {
        let name = "Default Alive Calculator"
        let main = NSMenu()

        let app = NSMenu(title: name)
        app.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        // Listed for discoverability; the key monitor above handles the keystroke first.
        // Shown as Esc, not ⌘⌫: a ⌘⌫ menu shortcut would fire inside a box too (menu key
        // equivalents run before the field editor), clearing everything instead of
        // deleting to the start of the box.
        let clear = edit.addItem(withTitle: "Clear All", action: #selector(clearInputs(_:)), keyEquivalent: "\u{1b}")
        clear.keyEquivalentModifierMask = []
        clear.target = self

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        for submenu in [app, edit, windowMenu] {
            main.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "").submenu = submenu
        }
        NSApp.windowsMenu = windowMenu
        return main
    }
}
