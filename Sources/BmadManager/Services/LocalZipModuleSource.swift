import Foundation

enum ZipError: LocalizedError {
    case notConfigured
    case zipNotFound(String)
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:           return "No marketing growth module .zip is configured."
        case .zipNotFound(let path):   return "Zip file not found: \(path)"
        case .extractionFailed(let m): return "Zip extraction failed: \(m)"
        }
    }
}

/// `ModuleSource` adapter that materialises the module by extracting a
/// local `.zip` into a fresh temp directory.
struct LocalZipModuleSource: ModuleSource {
    let zipPath: String

    func withModuleRoot<T>(_ body: (URL) async throws -> T) async throws -> T {
        let trimmed = zipPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw ZipError.notConfigured
        }
        let tmpDir = try LocalZipModuleSource.extract(zipPath: trimmed)
        defer { LocalZipModuleSource.cleanup(tmpDir) }
        let root = LocalZipModuleSource.moduleRoot(in: tmpDir)
        return try await body(root)
    }

    // MARK: - Internals (also exercised directly by LocalZipModuleSourceTests)

    /// Extracts the zip to a fresh /tmp/bmad-manager-<uuid>/ directory and returns its URL.
    static func extract(zipPath: String) throws -> URL {
        let expanded = (zipPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            throw ZipError.zipNotFound(expanded)
        }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bmad-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", expanded, "-d", tmpDir.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: tmpDir)
            throw ZipError.extractionFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            try? FileManager.default.removeItem(at: tmpDir)
            throw ZipError.extractionFailed(message)
        }
        return tmpDir
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// If `dir` contains exactly one non-junk subdirectory (the GitHub
    /// "Download ZIP" wrapper pattern, where the archive wraps everything
    /// in a single top-level folder named after the repo), returns that
    /// subdirectory so callers can pass the module root directly to
    /// `bmad-method install --custom-source`. Otherwise returns `dir`.
    static func moduleRoot(in dir: URL) -> URL {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return dir
        }
        let meaningful = entries.filter { $0.lastPathComponent != "__MACOSX" }
        guard meaningful.count == 1, let only = meaningful.first else {
            return dir
        }
        let isDir = (try? only.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isDir ? only : dir
    }
}
