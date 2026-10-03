import AppKit
import SwiftUI

extension Notification.Name {
    static let clearInputs = Notification.Name("clearInputs")
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var keyMonitor: Any?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        let controller = NSHostingController(rootView: CalculatorView())
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Default Alive Calculator"
        // The last input is the only thing this app remembers: no restored windows, no
        // saved frame. Opens centered every time.
        window.isRestorable = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate()

        // A local monitor runs before the field editor sees the key, which is what lets
        // Esc / C / ⌘⌫ clear everything even while a text field has focus. ⌘⌫ normally
        // deletes to line start; overriding it is intentional. Plain C is safe to steal
        // because no field accepts letters other than k/m/b, and ⌘C (copy) still passes.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let esc = event.keyCode == 53 && mods.isEmpty
            let c = event.charactersIgnoringModifiers?.lowercased() == "c" && mods.subtracting(.shift).isEmpty
            let cmdDelete = event.keyCode == 51 && mods == .command
            guard esc || c || cmdDelete else { return event }
            NotificationCenter.default.post(name: .clearInputs, object: nil)
            return nil
        }
    }

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
        let clear = edit.addItem(withTitle: "Clear All", action: #selector(clearInputs(_:)), keyEquivalent: "\u{8}")
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
