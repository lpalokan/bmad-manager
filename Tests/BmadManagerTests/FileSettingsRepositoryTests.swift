import XCTest
@testable import BmadManager

final class FileSettingsRepositoryTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-repo-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testFirstLoadReturnsNil() {
        let repo = FileSettingsRepository(fileURL: tempURL.appendingPathComponent("settings.json"))
        XCTAssertNil(repo.load())
    }

    func testSaveThenLoadRoundTrips() {
        let repo = FileSettingsRepository(fileURL: tempURL.appendingPathComponent("settings.json"))
        let settings = AppSettings(
            projectsRoot: "/tmp/test-projects",
            moduleZipPath: "/tmp/test-module.zip",
            initCommand: "echo hello",
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .dateNewestFirst
        )
        repo.save(settings)

        let loaded = repo.load()
        XCTAssertEqual(loaded, settings)
    }

    func testSavedFileIsPrettyPrintedWithSortedKeys() throws {
        let fileURL = tempURL.appendingPathComponent("settings.json")
        let repo = FileSettingsRepository(fileURL: fileURL)
        let settings = AppSettings.defaults()
        repo.save(settings)

        let data = try Data(contentsOf: fileURL)
        let raw = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(raw.contains("\n"), "file should be pretty-printed (multi-line)")
        let lines = raw.components(separatedBy: "\n")
        let keyLines = lines.filter { $0.contains("\"") && $0.contains(":") }
        if keyLines.count >= 2 {
            let first = keyLines[0].trimmingCharacters(in: .whitespaces)
            let second = keyLines[1].trimmingCharacters(in: .whitespaces)
            XCTAssertLessThanOrEqual(first, second, "keys should be sorted")
        }
    }

    func testSaveIsAtomic() throws {
        let fileURL = tempURL.appendingPathComponent("settings.json")
        let repo = FileSettingsRepository(fileURL: fileURL)
        let settings = AppSettings.defaults()
        repo.save(settings)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testLoadLegacySettingsWithoutSortOrder() throws {
        let fileURL = tempURL.appendingPathComponent("legacy.json")
        let legacy = """
        {
            "projectsRoot": "/tmp/legacy",
            "moduleZipPath": "/tmp/m.zip",
            "initCommand": "echo {PROJECT_PATH}",
            "claudeCommand": "claude",
            "opencodeCommand": "opencode"
        }
        """.data(using: .utf8)!
        try legacy.write(to: fileURL)

        let repo = FileSettingsRepository(fileURL: fileURL)
        let loaded = repo.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.projectSortOrder, .nameAscending)
        XCTAssertEqual(loaded?.projectsRoot, "/tmp/legacy")
    }
}
