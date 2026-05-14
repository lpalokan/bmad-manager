import Foundation

/// A `ModuleSource` produces a directory on disk containing the
/// marketing-growth module root, hands it to `body`, and cleans up
/// when `body` returns or throws.
///
/// The interface deliberately hides *how* the module was materialised —
/// a shallow git clone, a local zip extraction, or anything added later —
/// so `ProjectCreator` orchestrates without source-specific branching.
protocol ModuleSource {
    func withModuleRoot<T>(_ body: (URL) async throws -> T) async throws -> T
}

/// Maps an `AppSettings` to the concrete `ModuleSource` adapter for the
/// configured `moduleSourceKind`. Single dispatch point so
/// `ProjectCreator` stays oblivious to source kinds.
enum ModuleSourceFactory {
    static func make(for settings: AppSettings) -> ModuleSource {
        switch settings.moduleSourceKind {
        case .gitRepo:
            return GitRepoModuleSource(url: settings.moduleRepoURL, ref: settings.moduleRepoRef)
        case .localZip:
            return LocalZipModuleSource(zipPath: settings.moduleZipPath)
        }
    }
}
