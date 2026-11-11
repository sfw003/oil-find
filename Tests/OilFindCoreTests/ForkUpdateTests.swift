import XCTest
@testable import OilFindCore

final class ForkUpdateTests: XCTestCase {
    private func url(_ value: String) -> URL { URL(string: value)! }
    func testAssetIsPinnedToForkReleaseDownloads() {
        XCTAssertTrue(UpdateURLPolicy.asset(url("https://github.com/sfw003/oil-find/releases/download/v1.8.2+sfw.1/Oil-Find-macOS.zip"), allowLocalhost: false))
        for value in ["https://github.com/oil-oil/oil-find/releases/download/v1.8.2/test.zip",
                      "https://github.com/sfw003/other/releases/download/v1.8.2/test.zip",
                      "https://github.com/sfw003/oil-find/archive/refs/heads/main.zip",
                      "https://github.com/sfw003/oil-find/releases/download/v1.8.2/../test.zip",
                      "https://github.com/sfw003/oil-find/releases/download/v1.8.2/a%2Fb.zip",
                      "https://release-assets.githubusercontent.com/test.zip",
                      "https://github.com:8443/sfw003/oil-find/releases/download/v1.8.2/test.zip",
                      "http://github.com/sfw003/oil-find/releases/download/v1.8.2/test.zip",
                      "https://user@github.com/sfw003/oil-find/releases/download/v1.8.2/test.zip",
                      "https://github.com/sfw003/oil-find/releases/download/v1.8.2/test.zip?other=1",
                      "https://github.com/sfw003/oil-find/releases/download/v1.8.2/test.zip#fragment"] {
            XCTAssertFalse(UpdateURLPolicy.asset(url(value), allowLocalhost: false), value)
        }
    }
    func testManifestSourcesArePinnedToFork() {
        XCTAssertTrue(UpdateURLPolicy.manifest(UpdateClient.latestURL, allowLocalhost: false))
        XCTAssertTrue(UpdateURLPolicy.manifest(url("https://github.com/sfw003/oil-find/releases/download/v1.8.2/latest-v2.json"), allowLocalhost: false))
        XCTAssertFalse(UpdateURLPolicy.manifest(url("https://find.oiloil.org/updates/latest-v2.json"), allowLocalhost: false))
    }
    func testRedirectsAllowOnlyExactGitHubHTTPSHosts() {
        let source = UpdateClient.latestURL
        for host in ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"] {
            let target = url("https://" + host + "/asset?token=public-signed-url")
            XCTAssertTrue(UpdateURLPolicy.redirect(from: source, to: target, allowLocalhost: false))
            XCTAssertTrue(UpdateURLPolicy.redirect(from: target, to: source, allowLocalhost: false))
        }
        for value in ["https://github.com.evil.example/asset", "https://evil.github.com/asset", "https://example.com/asset",
                      "http://release-assets.githubusercontent.com/asset", "https://github.com:8443/asset",
                      "https://user:password@github.com/asset", "file:///tmp/asset", "http://127.0.0.1/asset"] {
            XCTAssertFalse(UpdateURLPolicy.redirect(from: source, to: url(value), allowLocalhost: false), value)
            XCTAssertFalse(UpdateURLPolicy.redirect(from: url(value), to: source, allowLocalhost: false), value)
        }
    }
    func testLocalhostExerciseRemainsExplicitAndIsolated() {
        let source = url("http://127.0.0.1:8123/latest.json"), target = url("http://127.0.0.1:8123/test.zip")
        XCTAssertFalse(UpdateURLPolicy.asset(target, allowLocalhost: false))
        XCTAssertTrue(UpdateURLPolicy.manifest(source, allowLocalhost: true))
        XCTAssertTrue(UpdateURLPolicy.asset(target, allowLocalhost: true))
        XCTAssertTrue(UpdateURLPolicy.redirect(from: source, to: target, allowLocalhost: true))
        XCTAssertFalse(UpdateURLPolicy.redirect(from: source, to: url("http://127.0.0.1:8124/test.zip"), allowLocalhost: true))
        XCTAssertFalse(UpdateURLPolicy.redirect(from: UpdateClient.latestURL, to: target, allowLocalhost: true))
        XCTAssertFalse(UpdateURLPolicy.redirect(from: source, to: UpdateClient.latestURL, allowLocalhost: true))
    }
    func testForkBuildsUpgradeSameUpstreamVersionInRunOrder() {
        XCTAssertGreaterThan(UpdateVersion("1.8.2", build: 1_000_001)!, UpdateVersion("1.8.2", build: 22)!)
        XCTAssertGreaterThan(UpdateVersion("1.8.2", build: 1_000_002)!, UpdateVersion("1.8.2", build: 1_000_001)!)
        XCTAssertLessThan(UpdateVersion("1.8.2", build: 1_000_002)!, UpdateVersion("1.8.3", build: 1)!)
        XCTAssertLessThan(UpdateVersion("1.8.2-sfw.1", build: 1_000_002)!, UpdateVersion("1.8.2", build: 22)!)
    }
}

final class ForkReleaseManifestTests: XCTestCase {
    func testGeneratedManifestMatchesPackagedApp() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["OILFIND_TEST_GENERATED_MANIFEST"], let app = environment["OILFIND_TEST_GENERATED_APP"] else {
            throw XCTSkip("Generated release assets are verified by Build App")
        }
        let manifest = try UpdateManifest.parse(Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertTrue(UpdateURLPolicy.asset(manifest.url, allowLocalhost: false))
        XCTAssertEqual(manifest.release, try SystemUpdateFiles().version(of: URL(fileURLWithPath: app)))
        try SystemUpdateFiles().verifyArchive(URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("Oil-Find-macOS.zip"), manifest: manifest)
    }
}
