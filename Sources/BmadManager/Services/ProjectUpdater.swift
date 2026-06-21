import Foundation

enum ProjectUpdateError: LocalizedError {
    case initCommandFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .initCommandFailed(let code):
            return "Update command exited with code \(code). See the output panel for details."
        }
    }
}

/// Re-installs the latest module over an existing project and refreshes the
/// managed AGENTS.md blocks. Sibling of `ProjectCreator`: it shares the same
/// `ModuleSource` seam and `runCommand` convention, but targets a folder that
/// already exists and never touches the user's data under `_bmad-output/`.
struct ProjectUpdater {
    let projectService: ProjectService
    let moduleSourceFor: (AppSettings) -> ModuleSource

    init(
        projectService: ProjectService,
        moduleSourceFor: @escaping (AppSettings) -> ModuleSource = ModuleSourceFactory.make
    ) {
        self.projectService = projectService
        self.moduleSourceFor = moduleSourceFor
    }

    /// Materialises a fresh module clone, re-runs the init command over the
    /// existing project folder, then re-injects both managed AGENTS.md blocks
    /// from that clone. The install is idempotent over an existing project
    /// (the same path the "Initialize existing folder…" flow exercises), so
    /// user content under `_bmad-output/` is left intact.
    func update(
        project: ProjectItem,
        settings: AppSettings,
        runCommand: (String, URL) async -> Int32 = { _, _ in 0 }
    ) async throws {
        let source = moduleSourceFor(settings)
        let projectURL = project.url

        try await source.withModuleRoot { moduleRoot, installerSource in
            let command = settings.initCommand
                .replacingOccurrences(of: "{PROJECT_PATH}", with: projectURL.path)
                .replacingOccurrences(of: "{MODULE_SOURCE}", with: installerSource)
                .replacingOccurrences(of: "{MODULE_PATH}", with: moduleRoot.path)
                .replacingOccurrences(of: "{PROJECT_NAME}", with: project.name)

            let exitCode = await runCommand(command, projectURL)
            if exitCode != 0 {
                throw ProjectUpdateError.initCommandFailed(exitCode)
            }

            // Refresh both managed AGENTS.md blocks from the fresh clone, while
            // it's still on disk (the source cleans the clone up on return).
            // Best-effort: a write hiccup shouldn't fail an otherwise-good
            // re-install.
            try? AgentsFileWriter.ensureBmadSection(in: projectURL)
            injectOkfBlock(from: moduleRoot, into: projectURL)
        }
    }

    /// Injects the `marketing-growth:okf` block when the fresh clone ships
    /// `templates/agents-okf-block.md`. Dormant until the companion repo adds
    /// that template — silently skipped (and not an error) when it's absent.
    private func injectOkfBlock(from moduleRoot: URL, into projectURL: URL) {
        let template = moduleRoot.appendingPathComponent("templates/agents-okf-block.md")
        guard let body = try? String(contentsOf: template, encoding: .utf8) else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? AgentsFileWriter.ensureManagedSection(
            in: projectURL, namespace: "marketing-growth:okf", body: trimmed)
    }
}
