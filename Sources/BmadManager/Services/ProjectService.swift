import Foundation
import AppKit

enum ProjectError: LocalizedError {
    case invalidName(String)
    case projectExists(String)
    case rootNotADirectory(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let message): return message
        case .projectExists(let name): return "A folder named '\(name)' already exists at the projects root."
        case .rootNotADirectory(let path): return "Projects root '\(path)' exists but is not a directory."
        }
    }
}

struct ProjectService {
    func listProjects(in rootPath: String) -> [ProjectItem] {
        let expanded = (rootPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { ProjectItem(url: $0) }
    }

    func createProjectFolder(name: String, in rootPath: String) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            throw ProjectError.invalidName("Project name cannot be empty.")
        }
        if trimmed.contains("/") || trimmed.contains(":") {
            throw ProjectError.invalidName("Project name cannot contain '/' or ':'.")
        }
        if trimmed.hasPrefix(".") {
            throw ProjectError.invalidName("Project name cannot start with '.'.")
        }

        let expanded = (rootPath as NSString).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: expanded, isDirectory: true)

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                throw ProjectError.rootNotADirectory(expanded)
            }
        } else {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        let projectURL = rootURL.appendingPathComponent(trimmed, isDirectory: true)
        if FileManager.default.fileExists(atPath: projectURL.path) {
            throw ProjectError.projectExists(trimmed)
        }
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: false)
        return projectURL
    }

    func trash(_ project: ProjectItem) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([project.url]) { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }
}
