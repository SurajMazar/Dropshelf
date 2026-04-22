import AppKit

final class ShelfWindowController: NSWindowController {
    private let store: ShelfStore
    private let viewController: ShelfViewController
    private(set) var isDocked = false
    private var preDockFrame: NSRect?
    private var pendingDockTask: DispatchWorkItem?
    private var isAnimating = false

    private static let floatingSize = NSSize(width: 360, height: 180)
    private static let dockedSize = NSSize(width: 48, height: 180)

    init(store: ShelfStore) {
        self.store = store
        self.viewController = ShelfViewController(store: store)
        let panel = ShelfPanel()
        panel.contentViewController = viewController
        super.init(window: panel)
        viewController.onDockToggle = { [weak self] in self?.toggleDock() }
        viewController.onUndockRequested = { [weak self] in self?.undock() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: panel
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard !isDocked, !isAnimating, let window else { return }

        pendingDockTask?.cancel()
        let snapshot = window.frame
        let task = DispatchWorkItem { [weak self] in
            self?.autoDockIfSettled(expectedFrame: snapshot)
        }
        pendingDockTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
    }

    private func autoDockIfSettled(expectedFrame: NSRect) {
        guard !isDocked, !isAnimating, let window else { return }
        guard window.frame == expectedFrame else { return } // still moving — next windowDidMove will reschedule
        guard NSEvent.pressedMouseButtons == 0 else { return } // user still holding mouse; wait
        guard let screen = window.screen ?? NSScreen.main else { return }
        let rightGap = screen.visibleFrame.maxX - window.frame.maxX
        if rightGap < 28 {
            dock()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func toggle(nearCursor: Bool) {
        guard let window else { return }
        if window.isVisible {
            hide()
        } else {
            show(nearCursor: nearCursor)
        }
    }

    func show(nearCursor: Bool) {
        guard let window else { return }

        if nearCursor {
            summonNearCursor()
            return
        }

        if isDocked {
            window.orderFrontRegardless()
            return
        }

        if window.frame.origin == .zero {
            centerInScreen(window)
        }
        window.orderFrontRegardless()
        window.makeKey()
    }

    private func summonNearCursor() {
        guard let window else { return }
        let target = cursorFloatingFrame()

        if isDocked {
            isDocked = false
            window.orderFrontRegardless()
            animateFrame(to: target) { [weak self] in
                self?.viewController.setDocked(false)
                self?.window?.makeKey()
            }
        } else {
            positionNearCursor(window)
            window.orderFrontRegardless()
            window.makeKey()
        }
    }

    private func cursorFloatingFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let size = Self.floatingSize
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 20)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
            origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - size.height - 8))
        }
        return NSRect(origin: origin, size: size)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func toggleDock() {
        isDocked ? undock() : dock()
    }

    func shakeToggle() {
        guard let window else { return }
        if window.isVisible && !isDocked {
            dock()
        } else {
            show(nearCursor: true)
        }
    }

    private func dock() {
        guard let window, !isDocked, !isAnimating else { return }
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first!
        preDockFrame = window.frame

        let visible = screen.visibleFrame
        let target = NSRect(
            x: visible.maxX - Self.dockedSize.width,
            y: visible.midY - Self.dockedSize.height / 2,
            width: Self.dockedSize.width,
            height: Self.dockedSize.height
        )

        isDocked = true
        viewController.setDocked(true)
        animateFrame(to: target)
    }

    private func undock() {
        guard let window, isDocked, !isAnimating else { return }
        let raw = preDockFrame ?? defaultFloatingFrame(near: window.frame)
        let target = clampToVisibleScreen(raw, size: Self.floatingSize)

        isDocked = false
        animateFrame(to: target) { [weak self] in
            self?.viewController.setDocked(false)
            self?.window?.makeKey()
        }
    }

    private func clampToVisibleScreen(_ rect: NSRect, size: NSSize) -> NSRect {
        guard let screen = window?.screen ?? NSScreen.main else { return rect }
        let visible = screen.visibleFrame
        var origin = rect.origin
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
        origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - size.height - 8))
        return NSRect(origin: origin, size: size)
    }

    private func animateFrame(to frame: NSRect, completion: (() -> Void)? = nil) {
        guard let window else { return }
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            self?.isAnimating = false
            completion?()
        })
    }

    private func defaultFloatingFrame(near reference: NSRect) -> NSRect {
        let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        var origin = NSPoint(
            x: reference.minX - Self.floatingSize.width - 12,
            y: reference.midY - Self.floatingSize.height / 2
        )
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - Self.floatingSize.width - 8))
        origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - Self.floatingSize.height - 8))
        return NSRect(origin: origin, size: Self.floatingSize)
    }

    private func positionNearCursor(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let size = Self.floatingSize
        if window.frame.size != size {
            window.setFrame(NSRect(origin: window.frame.origin, size: size), display: false)
        }
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 20)

        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
            origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - size.height - 8))
        }
        window.setFrameOrigin(origin)
    }

    private func centerInScreen(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let size = Self.floatingSize
        if window.frame.size != size {
            window.setFrame(NSRect(origin: window.frame.origin, size: size), display: false)
        }
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }
}
