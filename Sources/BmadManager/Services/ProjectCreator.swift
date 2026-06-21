import Foundation

enum ProjectCreationError: LocalizedError {
    case initCommandFailed(Int32)
    case contextImportFailed(sourceProject: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .initCommandFailed(let code):
            return "Init command exited with code \(code). See the output panel for details."
        case .contextImportFailed(let sourceProject, let reason):
            return "Project created, but importing the context from '\(sourceProject)' failed: \(reason)"
        }
    }
}

struct ProjectCreator {
    let projectService: ProjectService
    let contextService: CompanyContextService
    let moduleSourceFor: (AppSettings) -> ModuleSource

    init(
        projectService: ProjectService,
        contextService: CompanyContextService = CompanyContextService(),
        moduleSourceFor: @escaping (AppSettings) -> ModuleSource = ModuleSourceFactory.make
    ) {
        self.projectService = projectService
        self.contextService = contextService
        self.moduleSourceFor = moduleSourceFor
    }

    @discardableResult
    func create(
        name: String,
        settings: AppSettings,
        importingContextFrom context: CompanyContext? = nil,
        destination: URL? = nil,
        runCommand: (String, URL) async -> Int32 = { _, _ in 0 }
    ) async throws -> ProjectItem {
        // When `destination` is supplied the user picked an existing folder to
        // initialise in-place: use it as-is (don't mint a new folder under
        // projectsRoot, don't apply the must-not-exist guard). Otherwise keep
        // today's name → new-folder-under-projectsRoot behaviour.
        let projectURL: URL
        if let destination {
            projectURL = try projectService.useExistingFolder(at: destination).url
        } else {
            projectURL = try projectService.createProjectFolder(name: name, in: settings.projectsRoot)
        }
        let source = moduleSourceFor(settings)

        try await source.withModuleRoot { moduleRoot, installerSource in
            let command = settings.initCommand
                .replacingOccurrences(of: "{PROJECT_PATH}", with: projectURL.path)
                .replacingOccurrences(of: "{MODULE_SOURCE}", with: installerSource)
                .replacingOccurrences(of: "{MODULE_PATH}", with: moduleRoot.path)
                .replacingOccurrences(of: "{PROJECT_NAME}", with: name)

            let exitCode = await runCommand(command, projectURL)
            if exitCode != 0 {
                throw ProjectCreationError.initCommandFailed(exitCode)
            }
        }

        // bmad-method installs BMad's skills for Codex under `.agents/skills`
        // (which Codex auto-discovers) but emits no Codex `AGENTS.md`, so Codex
        // can't route BMad menu codes to the right skill. Write that routing
        // into the project's AGENTS.md. Best-effort: a missing bridge file
        // shouldn't fail an otherwise-successful project creation.
        try? AgentsFileWriter.ensureBmadSection(in: projectURL)

        // Seed the company context only after the init command succeeded —
        // a failed init keeps the project folder for inspection (partial-
        // state policy) but should not look half-bootstrapped.
        if let context {
            do {
                try contextService.importContext(context, into: projectURL)
            } catch {
                throw ProjectCreationError.contextImportFailed(
                    sourceProject: context.projectName,
                    reason: error.localizedDescription
                )
            }
        }

        let values = try? projectURL.resourceValues(forKeys: [.creationDateKey])
        return ProjectItem(url: projectURL, createdAt: values?.creationDate)
    }
}
