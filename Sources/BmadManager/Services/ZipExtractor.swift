import Foundation

enum ZipError: LocalizedError {
    case zipNotFound(String)
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .zipNotFound(let path): return "Zip file not found: \(path)"
        case .extractionFailed(let message): return "Zip extraction failed: \(message)"
        }
    }
}

enum ZipExtractor {
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
}
