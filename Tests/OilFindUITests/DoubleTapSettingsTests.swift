import XCTest
@testable import OilFindApp

final class DoubleTapSettingsTests: XCTestCase {
    func testTogglePersistsAndNotifiesWithoutRequestingPermissionInSnapshots() throws {
        let suite = "OilFindDoubleTapSettings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SettingsModel(snapshot: true, preferences: defaults)
        XCTAssertTrue(model.doubleTapControl)
        XCTAssertFalse(model.inputMonitoringGranted)
        var changed = 0; model.onDoubleTapControlChange = { changed += 1 }
        model.setDoubleTapControl(false)
        XCTAssertFalse(model.doubleTapControl)
        XCTAssertFalse(defaults.bool(forKey: "doubleTapControl"))
        model.setDoubleTapControl(true)
        XCTAssertTrue(model.doubleTapControl)
        XCTAssertTrue(defaults.bool(forKey: "doubleTapControl"))
        XCTAssertEqual(changed, 2)
    }
    func testShortcutAndPermissionCopyIsLocalized() {
        defer { L10n.snapshotChinese = nil }
        for chinese in [true, false] {
            L10n.snapshotChinese = chinese
            XCTAssertEqual(L10n.text("settings.doubleTapControl"), chinese ? "双击 ⌃ 唤起" : "Double-tap ⌃ to open")
            XCTAssertTrue(L10n.text("settings.inputMonitoringHint").contains(chinese ? "输入监控" : "Input Monitoring"))
            XCTAssertEqual(L10n.text("settings.inputMonitoringOpen"), chinese ? "打开输入监控设置" : "Open Input Monitoring Settings")
        }
    }
}
