import Foundation

public struct DoubleTapDetector {
    public struct Modifiers: OptionSet {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let command = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
        public static let function = Modifiers(rawValue: 1 << 4)
    }
    private let interval: TimeInterval
    private var controlDown = false
    private var firstPress: TimeInterval?
    private var released = false
    public init(interval: TimeInterval = 0.350) { self.interval = interval }
    public mutating func reset() { controlDown = false; firstPress = nil; released = false }
    public mutating func keyDown() { firstPress = nil; released = false }
    public mutating func flagsChanged(_ modifiers: Modifiers, at timestamp: TimeInterval) -> Bool {
        let wasDown = controlDown
        controlDown = modifiers.contains(.control)
        guard timestamp.isFinite, modifiers.subtracting(.control).isEmpty else { keyDown(); return false }
        // Aggregate Control state accepts either side, but never counts overlapping presses.
        guard controlDown != wasDown else { return false }
        if controlDown {
            if let firstPress, released, timestamp >= firstPress, timestamp - firstPress <= interval {
                keyDown(); return true
            }
            firstPress = timestamp; released = false
        } else if let firstPress, timestamp >= firstPress, timestamp - firstPress <= interval {
            released = true
        } else { keyDown() }
        return false
    }
}
