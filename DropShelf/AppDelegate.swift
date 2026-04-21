import AppKit
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ShelfStore()
    var windowController: ShelfWindowController!
    var shakeDetector: ShakeDetector!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = ShelfWindowController(store: store)

        KeyboardShortcuts.onKeyDown(for: .toggleShelf) { [weak self] in
            self?.windowController.toggle(nearCursor: true)
        }

        shakeDetector = ShakeDetector { [weak self] in
            self?.windowController.show(nearCursor: true)
        }
        shakeDetector.start()

        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shakeDetector?.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tray.fill", accessibilityDescription: "DropShelf")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show/Hide Shelf", action: #selector(toggleShelf), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear All", action: #selector(clearAll), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Grant Accessibility (for shake)…", action: #selector(openAccessibility), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DropShelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleShelf() {
        windowController.toggle(nearCursor: false)
    }

    @objc private func clearAll() {
        store.clear()
    }
}
