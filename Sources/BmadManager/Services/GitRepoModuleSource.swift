import Foundation

enum GitError: LocalizedError {
    case noRepoURLConfigured
    case gitNotAvailable(String)
    case cloneFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRepoURLConfigured:    return "No GitHub repository URL is configured."
        case .gitNotAvailable(let m): return "git is not available: \(m). Install Xcode Command Line Tools (xcode-select --install) or pick a local zip in Settings."
        case .cloneFailed(let m):     return "git clone failed: \(m)"
        }
    }
}

/// `ModuleSource` adapter that materialises the module by shallow-cloning
/// a git repository into a fresh temp directory. The clone root *is* the
/// module root — no wrapper descent needed (unlike GitHub "Download ZIP"
/// archives, which add a wrapper folder).
struct GitRepoModuleSource: ModuleSource {
    let url: String
    let ref: String

    func withModuleRoot<T>(_ body: (URL) async throws -> T) async throws -> T {
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else {
            throw GitError.noRepoURLConfigured
        }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-\(UUID().uuidString)", isDirectory: true)
        try GitRepoModuleSource.clone(url: trimmedURL, ref: ref, into: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        return try await body(tmpDir)
    }

    // MARK: - Internals

    static func clone(url: String, ref: String, into dir: URL) throws {
        // Empty ref → follow the repo's default branch.
        var args = ["clone", "--depth", "1"]
        let trimmedRef = ref.trimmingCharacters(in: .whitespaces)
        if !trimmedRef.isEmpty {
            args.append(contentsOf: ["--branch", trimmedRef])
        }
        args.append(url)
        args.append(dir.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw GitError.gitNotAvailable(error.localizedDescription)
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            try? FileManager.default.removeItem(at: dir)
            throw GitError.cloneFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
