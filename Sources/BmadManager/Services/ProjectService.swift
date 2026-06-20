import Foundation
import AppKit

enum ProjectError: LocalizedError {
    case invalidName(String)
    case projectExists(String)
    case rootNotADirectory(String)
    case folderNotADirectory(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let message): return message
        case .projectExists(let name): return "A folder named '\(name)' already exists at the projects root."
        case .rootNotADirectory(let path): return "Projects root '\(path)' exists but is not a directory."
        case .folderNotADirectory(let path): return "'\(path)' is not an existing folder."
        }
    }
}

struct ProjectService {
    func listProjects(
        in rootPath: String,
        sortedBy sortOrder: ProjectSortOrder = .nameAscending
    ) -> [ProjectItem] {
        let expanded = (rootPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let items: [ProjectItem] = entries.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
            guard (values?.isDirectory ?? false) else { return nil }
            return ProjectItem(url: url, createdAt: values?.creationDate)
        }
        return items.sorted(by: sortOrder.areInIncreasingOrder)
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

    /// Validates that `folder` is an existing directory and returns the
    /// matching `ProjectItem`. Unlike `createProjectFolder`, this is the
    /// "initialize into an existing folder" path: the folder is used as-is,
    /// so it must already exist and may be non-empty.
    func useExistingFolder(at folder: URL) throws -> ProjectItem {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw ProjectError.folderNotADirectory(folder.path)
        }
        let values = try? folder.resourceValues(forKeys: [.creationDateKey])
        return ProjectItem(url: folder, createdAt: values?.creationDate)
    }

    /// True when `folder` holds no visible entries. Used to decide whether
    /// initialising into an existing folder needs a destructive-overwrite
    /// confirmation (empty → proceed silently).
    func folderIsEmpty(_ folder: URL) -> Bool {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries.isEmpty
    }

    /// True when `folder` already looks like a BMAD install — a stronger
    /// signal than "non-empty" that re-running init could clobber an
    /// existing setup. Detects the common marker directories.
    func folderHasBmadInstall(_ folder: URL) -> Bool {
        for marker in ["bmad", ".bmad", "_cfg"] {
            var isDir: ObjCBool = false
            let candidate = folder.appendingPathComponent(marker)
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
               isDir.boolValue {
                return true
            }
        }
        return false
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
