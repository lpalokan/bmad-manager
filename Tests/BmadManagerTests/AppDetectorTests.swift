import XCTest
@testable import BmadManager

/// Covers how a coding agent's desktop app is *located*, which both
/// detection (Settings caption, Auto launch gate) and launch agree on.
///
/// The regression these guard against: a Codex GUI whose real
/// `CFBundleIdentifier` differs from the `com.openai.codex` we hardcode.
/// LaunchServices then can't resolve the bundle ID, so detection used to
/// report "not installed" and Auto silently fell through to the CLI even
/// though `/Applications/Codex.app` was sitting right there. Resolution
/// now falls back to scanning the standard Applications folders by app
/// name, so a side-loaded GUI is found and launched via `open -a`.
final class AppDetectorTests: XCTestCase {
    private var appsDir: URL!

    override func setUp() {
        super.setUp()
        appsDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-apps-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: appsDir)
        super.tearDown()
    }

    /// Drops a fake `<name>.app` bundle directory into the temp Applications
    /// folder and returns its URL.
    @discardableResult
    private func makeAppBundle(_ name: String) throws -> URL {
        let bundle = appsDir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        return bundle
    }

    // MARK: - Bundle-identifier path (LaunchServices)

    func testResolvesByBundleIdentifierWhenLaunchServicesFindsIt() throws {
        let lsURL = URL(fileURLWithPath: "/Applications/Codex.app")
        // The Applications scan would find nothing here, proving the
        // bundle-ID hit short-circuits before any filesystem scan.
        let resolved = AppDetector.resolveAppURL(
            .codex,
            bundleLookup: { id in id == "com.openai.codex" ? lsURL : nil },
            applicationDirectories: [appsDir]
        )

        XCTAssertEqual(resolved, lsURL)
    }

    // MARK: - Applications-folder fallback (side-loaded GUI)

    func testFallsBackToApplicationsScanWhenBundleIdUnknown() throws {
        let bundle = try makeAppBundle("Codex.app")

        let resolved = AppDetector.resolveAppURL(
            .codex,
            bundleLookup: { _ in nil },
            applicationDirectories: [appsDir]
        )

        XCTAssertEqual(resolved, bundle)
    }

    func testReturnsNilWhenNeitherBundleIdNorAppPresent() {
        let resolved = AppDetector.resolveAppURL(
            .codex,
            bundleLookup: { _ in nil },
            applicationDirectories: [appsDir]
        )

        XCTAssertNil(resolved)
    }

    // MARK: - isInstalled mirrors resolution

    func testIsInstalledTrueWhenAppFoundByScan() throws {
        try makeAppBundle("Codex.app")

        XCTAssertTrue(AppDetector.isInstalled(
            .codex,
            bundleLookup: { _ in nil },
            applicationDirectories: [appsDir]
        ))
    }

    func testIsInstalledFalseWhenNothingFound() {
        XCTAssertFalse(AppDetector.isInstalled(
            .codex,
            bundleLookup: { _ in nil },
            applicationDirectories: [appsDir]
        ))
    }
}
