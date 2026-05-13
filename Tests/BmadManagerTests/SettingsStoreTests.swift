import XCTest
@testable import BmadManager

final class SettingsStoreTests: XCTestCase {
    func testEmptyRepoYieldsDefaultsAndSaves() {
        let repo = InMemorySettingsRepository()
        let store = SettingsStore(repository: repo)

        XCTAssertEqual(store.settings, AppSettings.defaults())
        XCTAssertNotNil(repo.stored)
        XCTAssertEqual(repo.stored, AppSettings.defaults())
    }

    func testPrePopulatedRepoLoadsStoredValue() {
        let repo = InMemorySettingsRepository()
        let custom = AppSettings(
            projectsRoot: "/tmp/custom",
            moduleZipPath: "/tmp/custom.zip",
            initCommand: "custom command",
            claudeCommand: "claude",
            opencodeCommand: "opencode",
            projectSortOrder: .dateOldestFirst
        )
        repo.save(custom)

        let store = SettingsStore(repository: repo)
        XCTAssertEqual(store.settings, custom)
    }

    func testMutatingSettingsSavesThroughRepo() {
        let repo = InMemorySettingsRepository()
        let store = SettingsStore(repository: repo)

        store.settings.projectsRoot = "/tmp/updated"
        store.settings.moduleZipPath = "/tmp/updated.zip"

        let saved = repo.stored
        XCTAssertEqual(saved?.projectsRoot, "/tmp/updated")
        XCTAssertEqual(saved?.moduleZipPath, "/tmp/updated.zip")
    }

    func testResetRestoresDefaultsAndSaves() {
        let repo = InMemorySettingsRepository()
        let store = SettingsStore(repository: repo)

        store.settings.projectsRoot = "/tmp/changed"
        store.reset()

        XCTAssertEqual(store.settings, AppSettings.defaults())
        XCTAssertEqual(repo.stored, AppSettings.defaults())
    }
}
