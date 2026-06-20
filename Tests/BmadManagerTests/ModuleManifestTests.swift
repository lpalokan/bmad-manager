import XCTest
@testable import BmadManager

/// The "is this project behind the repo?" detection reads two YAML files —
/// the repo's `skills/module.yaml` (`code` + `module_version`) and the
/// installed project's `_bmad/_config/manifest.yaml` (`modules[].version`) —
/// and compares them with a leading-`v`-tolerant semver order. These pin the
/// hand-rolled parsing and comparison, including the conservative
/// "can't read it → not stale" bias that avoids false update badges.
final class ModuleManifestTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manifest-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Fixtures

    /// Writes `skills/module.yaml` under a fresh module root and returns it.
    @discardableResult
    private func makeModuleRoot(_ yaml: String) throws -> URL {
        let root = dir.appendingPathComponent("module-\(UUID().uuidString)", isDirectory: true)
        let skills = root.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try yaml.write(to: skills.appendingPathComponent("module.yaml"),
                       atomically: true, encoding: .utf8)
        return root
    }

    /// Writes `_bmad/_config/manifest.yaml` under a fresh project and returns it.
    @discardableResult
    private func makeProject(manifest: String) throws -> URL {
        let project = dir.appendingPathComponent("project-\(UUID().uuidString)", isDirectory: true)
        let config = project.appendingPathComponent("_bmad/_config", isDirectory: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try manifest.write(to: config.appendingPathComponent("manifest.yaml"),
                           atomically: true, encoding: .utf8)
        return project
    }

    /// The shape of a real installed manifest, parameterised on the
    /// marketing-growth version (and including an `installation.version` and a
    /// `core` module the parser must NOT confuse for the requested module).
    private func installedManifest(marketingGrowthVersion: String) -> String {
        """
        installation:
          version: 6.8.0
          installDate: 2026-06-20T13:15:54.411Z
        modules:
          - name: core
            version: 6.8.0
            source: built-in
          - name: bmb
            version: v2.0.0
            source: external
          - name: marketing-growth
            version: \(marketingGrowthVersion)
            source: custom
        ides:
          - claude-code
        """
    }

    // MARK: - readRepoModule

    func testReadsRepoModuleScalars() throws {
        let root = try makeModuleRoot("""
        code: marketing-growth
        name: "Marketing Growth Suite"
        module_version: 2.0.0
        default_selected: false
        """)

        let module = ModuleManifest.readRepoModule(atModuleRoot: root)

        XCTAssertEqual(module, ModuleManifest.RepoModule(code: "marketing-growth", version: "2.0.0"))
    }

    func testReadsRepoModuleWithQuotedValueAndComments() throws {
        let root = try makeModuleRoot("""
        # leading comment
        name: "Marketing Growth Suite"
        code: "marketing-growth"
        module_version: "2.1.3"
        """)

        let module = ModuleManifest.readRepoModule(atModuleRoot: root)

        XCTAssertEqual(module?.code, "marketing-growth")
        XCTAssertEqual(module?.version, "2.1.3")
    }

    func testReadRepoModuleMissingFileReturnsNil() {
        let root = dir.appendingPathComponent("no-such-module", isDirectory: true)
        XCTAssertNil(ModuleManifest.readRepoModule(atModuleRoot: root))
    }

    func testReadRepoModuleMissingScalarReturnsNil() throws {
        let root = try makeModuleRoot("""
        code: marketing-growth
        name: "Marketing Growth Suite"
        """)

        XCTAssertNil(ModuleManifest.readRepoModule(atModuleRoot: root),
                     "no module_version → can't tell → nil")
    }

    func testReadRepoModuleIgnoresNestedKeys() throws {
        // A `module_version`-looking key nested under another block must not be
        // mistaken for the top-level scalar.
        let root = try makeModuleRoot("""
        code: marketing-growth
        questions:
          module_version: 9.9.9
        module_version: 2.0.0
        """)

        XCTAssertEqual(ModuleManifest.readRepoModule(atModuleRoot: root)?.version, "2.0.0")
    }

    // MARK: - installedVersion

    func testInstalledVersionFromManifestList() throws {
        let project = try makeProject(manifest: installedManifest(marketingGrowthVersion: "2.0.0"))

        XCTAssertEqual(
            ModuleManifest.installedVersion(ofModule: "marketing-growth", inProject: project),
            "2.0.0")
        XCTAssertEqual(
            ModuleManifest.installedVersion(ofModule: "core", inProject: project),
            "6.8.0")
    }

    func testInstalledVersionPreservesVPrefix() throws {
        let project = try makeProject(manifest: installedManifest(marketingGrowthVersion: "2.0.0"))

        XCTAssertEqual(
            ModuleManifest.installedVersion(ofModule: "bmb", inProject: project),
            "v2.0.0", "the raw value is returned; the v-strip happens only at compare time")
    }

    func testInstalledVersionDoesNotPickUpInstallationVersion() throws {
        // A manifest with no marketing-growth module must return nil even
        // though `installation.version` exists at the top.
        let project = try makeProject(manifest: """
        installation:
          version: 6.8.0
        modules:
          - name: core
            version: 6.8.0
        """)

        XCTAssertNil(ModuleManifest.installedVersion(ofModule: "marketing-growth", inProject: project))
    }

    func testInstalledVersionMissingManifestReturnsNil() {
        let project = dir.appendingPathComponent("no-manifest", isDirectory: true)
        XCTAssertNil(ModuleManifest.installedVersion(ofModule: "marketing-growth", inProject: project))
    }

    func testInstalledVersionMalformedManifestReturnsNil() throws {
        let project = try makeProject(manifest: "this is not a modules list at all\n")
        XCTAssertNil(ModuleManifest.installedVersion(ofModule: "marketing-growth", inProject: project))
    }

    // MARK: - isOlder

    func testIsOlderBasic() {
        XCTAssertTrue(ModuleManifest.isOlder("2.0.0", than: "2.1.0"))
        XCTAssertTrue(ModuleManifest.isOlder("1.9.0", than: "2.0.0"))
        XCTAssertFalse(ModuleManifest.isOlder("2.1.0", than: "2.0.0"))
    }

    func testIsOlderStripsVPrefix() {
        XCTAssertTrue(ModuleManifest.isOlder("v2.0.0", than: "2.1.0"))
        XCTAssertFalse(ModuleManifest.isOlder("2.1.0", than: "v2.0.0"))
        XCTAssertFalse(ModuleManifest.isOlder("v2.0.0", than: "2.0.0"))
    }

    func testIsOlderEqualIsNotOlder() {
        XCTAssertFalse(ModuleManifest.isOlder("2.0.0", than: "2.0.0"))
    }

    func testIsOlderDifferentComponentCounts() {
        XCTAssertTrue(ModuleManifest.isOlder("2.0", than: "2.0.1"))
        XCTAssertFalse(ModuleManifest.isOlder("2.0.0", than: "2.0"))
    }

    // MARK: - isProjectStale

    func testProjectStaleWhenInstalledBehindRepo() throws {
        let project = try makeProject(manifest: installedManifest(marketingGrowthVersion: "2.0.0"))
        let repo = ModuleManifest.RepoModule(code: "marketing-growth", version: "2.1.0")

        XCTAssertTrue(ModuleManifest.isProjectStale(projectURL: project, repoModule: repo))
    }

    func testProjectNotStaleWhenCurrent() throws {
        let project = try makeProject(manifest: installedManifest(marketingGrowthVersion: "2.1.0"))
        let repo = ModuleManifest.RepoModule(code: "marketing-growth", version: "2.1.0")

        XCTAssertFalse(ModuleManifest.isProjectStale(projectURL: project, repoModule: repo))
    }

    func testProjectNotStaleWhenModuleAbsent() throws {
        let project = try makeProject(manifest: """
        modules:
          - name: core
            version: 6.8.0
        """)
        let repo = ModuleManifest.RepoModule(code: "marketing-growth", version: "2.1.0")

        XCTAssertFalse(ModuleManifest.isProjectStale(projectURL: project, repoModule: repo))
    }

    func testProjectNotStaleWhenManifestMissing() {
        let project = dir.appendingPathComponent("bare", isDirectory: true)
        let repo = ModuleManifest.RepoModule(code: "marketing-growth", version: "2.1.0")

        XCTAssertFalse(ModuleManifest.isProjectStale(projectURL: project, repoModule: repo))
    }

    func testProjectStaleWhenInstalledNonComparable() throws {
        // A non-comparable installed version (e.g. `garbage`) against a real
        // repo semver can't be verified current, so it must be flagged for a
        // reinstall — not silently treated as up to date (#76).
        let project = try makeProject(manifest: """
        modules:
          - name: marketing-growth
            version: garbage
        """)
        let repo = ModuleManifest.RepoModule(code: "marketing-growth", version: "2.1.0")

        XCTAssertTrue(ModuleManifest.isProjectStale(projectURL: project, repoModule: repo),
                      "an unverifiable installed version vs a real repo semver needs reinstall")
    }

    func testProjectStaleWhenInstalledIsBranchRef() throws {
        // The canonical #76 case: legacy installs stamped the branch name
        // `main` instead of a semver, so the project must offer an update.
        let project = try makeProject(manifest: """
        modules:
          - name: marketing-growth
            version: main
        """)
        let repo = ModuleManifest.RepoModule(code: "marketing-growth", version: "2.1.0")

        XCTAssertTrue(ModuleManifest.isProjectStale(projectURL: project, repoModule: repo))
    }

    func testProjectStaleWhenInstalledIsEmpty() throws {
        let project = try makeProject(manifest: """
        modules:
          - name: marketing-growth
            version: ""
        """)
        let repo = ModuleManifest.RepoModule(code: "marketing-growth", version: "2.1.0")

        XCTAssertTrue(ModuleManifest.isProjectStale(projectURL: project, repoModule: repo))
    }

    func testProjectNotStaleWhenRepoVersionNonComparable() throws {
        // If the repo version isn't itself comparable there's nothing to
        // compare against — stay conservative and don't badge.
        let project = try makeProject(manifest: """
        modules:
          - name: marketing-growth
            version: main
        """)
        let repo = ModuleManifest.RepoModule(code: "marketing-growth", version: "main")

        XCTAssertFalse(ModuleManifest.isProjectStale(projectURL: project, repoModule: repo))
    }
}
