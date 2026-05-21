import Foundation

enum ProjectCreationError: LocalizedError {
    case initCommandFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .initCommandFailed(let code):
            return "Init command exited with code \(code). See the output panel for details."
        }
    }
}

struct ProjectCreator {
    let projectService: ProjectService
    let moduleSourceFor: (AppSettings) -> ModuleSource

    init(
        projectService: ProjectService,
        moduleSourceFor: @escaping (AppSettings) -> ModuleSource = ModuleSourceFactory.make
    ) {
        self.projectService = projectService
        self.moduleSourceFor = moduleSourceFor
    }

    @discardableResult
    func create(
        name: String,
        settings: AppSettings,
        runCommand: (String, URL) async -> Int32 = { _, _ in 0 }
    ) async throws -> ProjectItem {
        let projectURL = try projectService.createProjectFolder(name: name, in: settings.projectsRoot)
        let source = moduleSourceFor(settings)

        try await source.withModuleRoot { moduleRoot in
            let command = settings.initCommand
                .replacingOccurrences(of: "{PROJECT_PATH}", with: projectURL.path)
                .replacingOccurrences(of: "{MODULE_PATH}", with: moduleRoot.path)
                .replacingOccurrences(of: "{PROJECT_NAME}", with: name)

            let exitCode = await runCommand(command, projectURL)
            if exitCode != 0 {
                throw ProjectCreationError.initCommandFailed(exitCode)
            }
        }

        let values = try? projectURL.resourceValues(forKeys: [.creationDateKey])
        return ProjectItem(url: projectURL, createdAt: values?.creationDate)
    }
}
