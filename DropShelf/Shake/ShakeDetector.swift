import AppKit

final class ShakeDetector {
    private let onShake: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var samples: [(point: NSPoint, time: TimeInterval)] = []
    private var lastTrigger: TimeInterval = 0

    private let windowSeconds: TimeInterval = 0.35
    private let requiredReversals = 3
    private let minAverageSpeed: CGFloat = 900
    private let debounceSeconds: TimeInterval = 0.8
    private let minDxForReversal: CGFloat = 2

    init(onShake: @escaping () -> Void) {
        self.onShake = onShake
    }

    func start() {
        requestAccessibilityIfNeeded()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    private func requestAccessibilityIfNeeded() {
        let options: CFDictionary = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func handle(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        let point = NSEvent.mouseLocation
        samples.append((point, now))

        let cutoff = now - windowSeconds
        while let first = samples.first, first.time < cutoff {
            samples.removeFirst()
        }

        guard samples.count >= 4 else { return }

        var reversals = 0
        var totalDistance: CGFloat = 0
        var totalTime: TimeInterval = 0
        var previousDx: CGFloat = 0
        for i in 1..<samples.count {
            let dx = samples[i].point.x - samples[i - 1].point.x
            let dy = samples[i].point.y - samples[i - 1].point.y
            totalDistance += sqrt(dx * dx + dy * dy)
            totalTime += samples[i].time - samples[i - 1].time
            if abs(dx) > minDxForReversal {
                if previousDx != 0, (previousDx > 0) != (dx > 0) {
                    reversals += 1
                }
                previousDx = dx
            }
        }
        let avgSpeed = totalTime > 0 ? totalDistance / CGFloat(totalTime) : 0

        if reversals >= requiredReversals,
           avgSpeed >= minAverageSpeed,
           now - lastTrigger > debounceSeconds {
            lastTrigger = now
            samples.removeAll()
            DispatchQueue.main.async { [weak self] in self?.onShake() }
        }
    }
}
