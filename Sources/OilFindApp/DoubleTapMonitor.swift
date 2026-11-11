import AppKit
import OilFindCore

final class DoubleTapMonitor {
    static var hasPermission: Bool { CGPreflightListenEventAccess() }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = DoubleTapDetector()
    private var requestedPermission = false
    private var generation = 0
    private let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
    @discardableResult func start(requestPermission: Bool = true) -> Bool {
        if !Self.hasPermission, requestPermission, !requestedPermission {
            requestedPermission = true
            _ = CGRequestListenEventAccess()
        }
        guard Self.hasPermission else { stop(); return false }
        if tap != nil { return true }
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue) | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                         eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            Unmanaged<DoubleTapMonitor>.fromOpaque(context).takeUnretainedValue().receive(type, event)
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap); return false
        }
        self.tap = tap; self.source = source
        detector.reset()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    func stop() {
        generation += 1
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; detector.reset()
    }
    private func receive(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            detector.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        if type == .keyDown { detector.keyDown(); return }
        guard type == .flagsChanged else { return }
        var modifiers: DoubleTapDetector.Modifiers = []
        for (flag, value) in [(CGEventFlags.maskControl, DoubleTapDetector.Modifiers.control),
                              (.maskCommand, .command), (.maskAlternate, .option), (.maskShift, .shift), (.maskSecondaryFn, .function)] {
            if event.flags.contains(flag) { modifiers.insert(value) }
        }
        guard detector.flagsChanged(modifiers, at: TimeInterval(event.timestamp) / 1_000_000_000) else { return }
        let generation = self.generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tap != nil, self.generation == generation else { return }
            self.handler()
        }
    }
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
    }
    deinit { stop() }
}
