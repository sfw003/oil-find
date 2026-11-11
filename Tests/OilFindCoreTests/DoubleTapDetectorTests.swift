import XCTest
@testable import OilFindCore

final class DoubleTapDetectorTests: XCTestCase {
    func testTwoSeparateControlPressesTriggerOnSecondDown() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.flagsChanged(.control, at: 0))
        XCTAssertFalse(detector.flagsChanged([], at: 0.1))
        XCTAssertTrue(detector.flagsChanged(.control, at: 0.2))
        XCTAssertFalse(detector.flagsChanged([], at: 0.3))
    }
    func testIntervalBoundaryIsInclusive() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.flagsChanged(.control, at: 0))
        XCTAssertFalse(detector.flagsChanged([], at: 0.1))
        XCTAssertTrue(detector.flagsChanged(.control, at: 0.350))
    }
    func testSlowSecondPressStartsANewPair() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.flagsChanged(.control, at: 0))
        XCTAssertFalse(detector.flagsChanged([], at: 0.1))
        XCTAssertFalse(detector.flagsChanged(.control, at: 0.351))
        XCTAssertFalse(detector.flagsChanged([], at: 0.4))
        XCTAssertTrue(detector.flagsChanged(.control, at: 0.5))
    }
    func testLongHoldIsNotATapEvenWithAShortReleaseGap() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.flagsChanged(.control, at: 0))
        XCTAssertFalse(detector.flagsChanged([], at: 1))
        XCTAssertFalse(detector.flagsChanged(.control, at: 1.1))
    }
    func testControlCThenControlDoesNotTrigger() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.flagsChanged(.control, at: 0))
        detector.keyDown()
        XCTAssertFalse(detector.flagsChanged([], at: 0.1))
        XCTAssertFalse(detector.flagsChanged(.control, at: 0.2))
        XCTAssertFalse(detector.flagsChanged([], at: 0.25))
        XCTAssertTrue(detector.flagsChanged(.control, at: 0.3))
    }
    func testOrdinaryKeyBetweenTapsCancelsPair() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.flagsChanged(.control, at: 0))
        XCTAssertFalse(detector.flagsChanged([], at: 0.1))
        detector.keyDown()
        XCTAssertFalse(detector.flagsChanged(.control, at: 0.2))
    }
    func testOtherModifiersCancelWhileHeldAndBetweenTaps() {
        for modifier in [DoubleTapDetector.Modifiers.command, .option, .shift, .function] {
            var detector = DoubleTapDetector()
            XCTAssertFalse(detector.flagsChanged(.control, at: 0))
            XCTAssertFalse(detector.flagsChanged([.control, modifier], at: 0.05))
            XCTAssertFalse(detector.flagsChanged(.control, at: 0.1))
            XCTAssertFalse(detector.flagsChanged([], at: 0.15))
            XCTAssertFalse(detector.flagsChanged(.control, at: 0.2))
            XCTAssertFalse(detector.flagsChanged([], at: 0.25))
            XCTAssertFalse(detector.flagsChanged(modifier, at: 0.26))
            XCTAssertFalse(detector.flagsChanged([], at: 0.27))
            XCTAssertFalse(detector.flagsChanged(.control, at: 0.3))
        }
    }
    func testReleasingAnotherModifierWhileControlIsHeldDoesNotStartATap() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.flagsChanged([.control, .shift], at: 0))
        XCTAssertFalse(detector.flagsChanged(.control, at: 0.05))
        XCTAssertFalse(detector.flagsChanged([], at: 0.1))
        XCTAssertFalse(detector.flagsChanged(.control, at: 0.2))
    }
    func testOverlappingLeftAndRightControlAreOnePress() {
        var detector = DoubleTapDetector()
        // Either side maps to .control; overlapping presses keep the aggregate flag set.
        XCTAssertFalse(detector.flagsChanged(.control, at: 0))
        XCTAssertFalse(detector.flagsChanged(.control, at: 0.05))
        XCTAssertFalse(detector.flagsChanged(.control, at: 0.1))
        XCTAssertFalse(detector.flagsChanged([], at: 0.15))
        XCTAssertTrue(detector.flagsChanged(.control, at: 0.2))
    }
    func testTripleTapTriggersOnlyOnceAndNextPairStillWorks() {
        var detector = DoubleTapDetector(), triggers = 0
        for time in [0.0, 0.1, 0.2] {
            if detector.flagsChanged(.control, at: time) { triggers += 1 }
            XCTAssertFalse(detector.flagsChanged([], at: time + 0.04))
        }
        XCTAssertEqual(triggers, 1)
        XCTAssertTrue(detector.flagsChanged(.control, at: 0.3))
    }
    func testResetDiscardsPendingPressAndRelease() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.flagsChanged(.control, at: 0))
        XCTAssertFalse(detector.flagsChanged([], at: 0.1))
        detector.reset()
        XCTAssertFalse(detector.flagsChanged(.control, at: 0.2))
    }
    func testOutOfOrderTimestampDoesNotTrigger() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.flagsChanged(.control, at: 1))
        XCTAssertFalse(detector.flagsChanged([], at: 1.1))
        XCTAssertFalse(detector.flagsChanged(.control, at: 0.9))
    }
    func testPreferenceDefaultsOnAndPreservesOptOut() throws {
        let suite = "OilFindDoubleTap-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsPreferences.register(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: "doubleTapControl"))
        defaults.set(false, forKey: "doubleTapControl")
        SettingsPreferences.register(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: "doubleTapControl"))
    }
}
