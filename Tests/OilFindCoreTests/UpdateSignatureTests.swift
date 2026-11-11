import XCTest
import Security
@testable import OilFindCore

private func makeRequirement(_ source: String) throws -> SecRequirement {
    var requirement: SecRequirement?
    XCTAssertEqual(SecRequirementCreateWithString(source as CFString, [], &requirement), errSecSuccess)
    return try XCTUnwrap(requirement)
}

private func assertSignatureRejected(_ app: URL, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try SystemUpdateSignature().validate(app), file: file, line: line) {
        XCTAssertEqual($0 as? UpdateFailure, .signature, file: file, line: line)
    }
}

final class UpdateSignatureTests: XCTestCase {
    func testDefaultUpdateFeedIsForkV2() {
        XCTAssertEqual(UpdateClient.latestURL.absoluteString, "https://github.com/sfw003/oil-find/releases/latest/download/latest-v2.json")
    }
    func testMatchingRunningDesignatedRequirementIsAccepted() throws {
        let signing = CodeSigning()
        signing.running = try makeRequirement("identifier \"running\"")
        signing.valid = true
        XCTAssertNoThrow(try SystemUpdateSignature(codeSigning: signing).validate(URL(fileURLWithPath: "/test/Oil Find.app")))
        XCTAssertEqual(signing.attempts, 1)
    }
    func testDifferentSignerIsRejectedWithoutFallback() throws {
        let signing = CodeSigning()
        signing.running = try makeRequirement("identifier \"running\"")
        XCTAssertThrowsError(try SystemUpdateSignature(codeSigning: signing).validate(URL(fileURLWithPath: "/test/Oil Find.app"))) {
            XCTAssertEqual($0 as? UpdateFailure, .signature)
        }
        XCTAssertEqual(signing.attempts, 1)
    }
    func testMissingRunningRequirementFailsClosed() {
        let signing = CodeSigning(); signing.valid = true
        XCTAssertThrowsError(try SystemUpdateSignature(codeSigning: signing).validate(URL(fileURLWithPath: "/test/Oil Find.app"))) {
            XCTAssertEqual($0 as? UpdateFailure, .signature)
        }
        XCTAssertEqual(signing.attempts, 0)
    }
}

private final class CodeSigning: UpdateCodeSigning {
    var running: SecRequirement?
    var valid = false
    private(set) var attempts = 0
    func runningDesignatedRequirement() -> SecRequirement? { running }
    func validate(_ app: URL, against requirement: SecRequirement) -> Bool {
        attempts += 1
        return requirement === running && valid
    }
}

final class UpdateSignatureIntegrationTests: XCTestCase {
    private func identity(_ environmentKey: String) throws -> String {
        guard let identity = ProcessInfo.processInfo.environment[environmentKey], !identity.isEmpty else {
            throw XCTSkip("Set \(environmentKey) to run real codesign validation")
        }
        return identity
    }

    func testRealDeveloperIDCandidateMustMatchRunningRequirement() throws {
        let identity = try identity("OILFIND_TEST_DEVELOPER_IDENTITY")
        try withSignedApp(identity: identity) { app in
            assertSignatureRejected(app)
            let signing = RunningRequirementCodeSigning(running: try designatedRequirement(for: app))
            XCTAssertNoThrow(try SystemUpdateSignature(codeSigning: signing).validate(app))
            try withSignedApp(identifier: "com.oiloil.find.invalid", identity: identity) { other in
                XCTAssertThrowsError(try SystemUpdateSignature(codeSigning: signing).validate(other))
            }
        }
    }

    func testAdHocCandidateIsRejected() throws {
        try withSignedApp(identity: "-") { app in
            assertSignatureRejected(app)
        }
    }

    func testRealSelfSignedUpdatesRequireSameIdentityAcrossBuilds() throws {
        let identity = try identity("OILFIND_TEST_SELF_SIGNED_IDENTITY")
        try withSignedApp(identity: identity) { app in
            assertSignatureRejected(app)
            let signing = RunningRequirementCodeSigning(running: try designatedRequirement(for: app))
            try withSignedApp(identity: identity, build: 2) { successor in
                XCTAssertNoThrow(try SystemUpdateSignature(codeSigning: signing).validate(successor))
                try Data("tampered".utf8).write(to: successor.appendingPathComponent("Contents/Frameworks/OilFindHelper"))
                XCTAssertThrowsError(try SystemUpdateSignature(codeSigning: signing).validate(successor))
            }
            try withSignedApp(identity: "-") { other in
                XCTAssertThrowsError(try SystemUpdateSignature(codeSigning: signing).validate(other))
            }
        }
    }

    func testRealDeveloperIDCandidateRejectsTamperedNestedCode() throws {
        let identity = try identity("OILFIND_TEST_DEVELOPER_IDENTITY")
        try withSignedApp(identity: identity) { app in
            try Data("tampered".utf8).write(to: app.appendingPathComponent("Contents/Frameworks/OilFindHelper"))
            assertSignatureRejected(app)
        }
    }

    private func designatedRequirement(for app: URL) throws -> SecRequirement {
        var candidate: SecStaticCode?, requirement: SecRequirement?
        XCTAssertEqual(SecStaticCodeCreateWithPath(app as CFURL, [], &candidate), errSecSuccess)
        XCTAssertEqual(SecCodeCopyDesignatedRequirement(try XCTUnwrap(candidate), [], &requirement), errSecSuccess)
        return try XCTUnwrap(requirement)
    }

    private func withSignedApp(identifier: String = "com.oiloil.find", identity: String, build: Int = 1, _ body: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("oilfind-signature-" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Oil Find.app", isDirectory: true)
        let executable = app.appendingPathComponent("Contents/MacOS/OilFind")
        let helper = app.appendingPathComponent("Contents/Frameworks/OilFindHelper")
        try fm.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleExecutable": "OilFind",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": String(build),
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: helper)
        try sign(helper, identity: identity, identifier: identifier + ".helper")
        try sign(app, identity: identity, identifier: identifier)
        try body(app)
    }

    private func sign(_ code: URL, identity: String, identifier: String) throws {
        let task = Process(), output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["--force", "--sign", identity, "--identifier", identifier, "--timestamp=none", code.path]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = output
        task.standardError = output
        try task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw NSError(domain: "UpdateSignatureIntegrationTests", code: Int(task.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self),
            ])
        }
    }
}

private final class RunningRequirementCodeSigning: UpdateCodeSigning {
    private let running: SecRequirement
    private let system = SystemUpdateCodeSigning()

    init(running: SecRequirement) { self.running = running }
    func runningDesignatedRequirement() -> SecRequirement? { running }
    func validate(_ app: URL, against requirement: SecRequirement) -> Bool {
        system.validate(app, against: requirement)
    }
}
