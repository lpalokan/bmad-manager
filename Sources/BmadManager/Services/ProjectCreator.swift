import Foundation

enum ProjectCreationError: LocalizedError {
    case noModuleZipConfigured
    case initCommandFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .noModuleZipConfigured:
            return "No marketing growth module .zip is configured."
        case .initCommandFailed(let code):
            return "Init command exited with code \(code). See the output panel for details."
        }
    }
}

struct ProjectCreator {
    let projectService: ProjectService

    @discardableResult
    func create(
        name: String,
        settings: AppSettings,
        runner: CommandRunner
    ) async throws -> ProjectItem {
        let moduleZip = settings.moduleZipPath.trimmingCharacters(in: .whitespaces)
        guard !moduleZip.isEmpty else {
            throw ProjectCreationError.noModuleZipConfigured
        }

        let projectURL = try projectService.createProjectFolder(name: name, in: settings.projectsRoot)

        try await ZipExtractor.withExtractedModule(zipPath: moduleZip) { moduleRoot in
            let modulePath = moduleRoot.path

            let command = settings.initCommand
                .replacingOccurrences(of: "{PROJECT_PATH}", with: projectURL.path)
                .replacingOccurrences(of: "{MODULE_PATH}", with: modulePath)
                .replacingOccurrences(of: "{PROJECT_NAME}", with: name)

            let exitCode = await runner.run(command: command, cwd: projectURL)
            if exitCode != 0 {
                throw ProjectCreationError.initCommandFailed(exitCode)
            }
        }

        let values = try? projectURL.resourceValues(forKeys: [.creationDateKey])
        return ProjectItem(url: projectURL, createdAt: values?.creationDate)
    }
}
