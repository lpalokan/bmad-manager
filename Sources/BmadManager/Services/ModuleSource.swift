import Foundation

/// A `ModuleSource` produces a directory on disk containing the
/// marketing-growth module root, hands it to `body` along with the
/// **installer source** string to feed `bmad-method --custom-source`, and
/// cleans up when `body` returns or throws.
///
/// The interface deliberately hides *how* the module was materialised —
/// a shallow git clone, a local zip extraction, or anything added later —
/// so `ProjectCreator` orchestrates without source-specific branching.
///
/// `moduleRoot` is always a local directory (post-install steps read the
/// module tree from it). `installerSource` is what the installer should
/// record in `manifest.yaml`: a **GitHub URL** (so the install is recorded
/// as `repoUrl` + `sha` + a real version) for the git source, or the local
/// module-root path for the local-zip source (correctly recorded as local).
protocol ModuleSource {
    func withModuleRoot<T>(
        _ body: (_ moduleRoot: URL, _ installerSource: String) async throws -> T
    ) async throws -> T
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
