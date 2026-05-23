import Foundation

/// Resolves a coding-agent command (e.g. `claude`, `opencode`, `pi`) to
/// an absolute file path by walking `PATH`. The Settings dialog calls
/// this so the user knows whether the bare-name defaults are reachable
/// before they need to browse for a binary.
///
/// Behaviour:
///   * Bare names are looked up under every `PATH` entry; only files
///     that pass `FileManager.isExecutableFile(atPath:)` count.
///   * A command containing `/` is treated as an explicit absolute or
///     relative path and checked directly — no PATH lookup, no
///     executable-bit check, because the user pointed at it on purpose.
///   * Empty/whitespace-only input always returns `nil`.
///
/// The `path` argument is exposed so tests can pin it without mutating
/// the process environment.
enum PathDetector {
    static func detect(
        _ command: String,
        path: String? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("/") {
            return fileManager.fileExists(atPath: trimmed) ? trimmed : nil
        }

        let raw = path ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        for entry in raw.split(separator: ":", omittingEmptySubsequences: false) {
            let dir = String(entry)
            if dir.isEmpty { continue }
            let candidate = (dir as NSString).appendingPathComponent(trimmed)
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
