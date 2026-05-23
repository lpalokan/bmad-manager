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
/// the process environment. When `path` is `nil` we use the user's
/// login-shell PATH (see `shellPath()`) rather than
/// `ProcessInfo.environment["PATH"]` — a `.app` launched from Finder
/// inherits only `/usr/bin:/bin:/usr/sbin:/sbin`, so Homebrew, npm
/// globals, asdf shims, etc. would otherwise be reported as missing
/// even though every Terminal session can find them.
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

        let raw = path ?? shellPath()
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

    /// Returns the PATH the user's interactive login shell exports,
    /// captured once per app run. Spawning a shell on every keystroke
    /// would be wasteful, and a user editing `~/.zshrc` mid-session can
    /// just relaunch the app to pick the new PATH up.
    static func shellPath() -> String {
        if let cached = cachedShellPath { return cached }
        let resolved = resolveShellPath()
        cachedShellPath = resolved
        return resolved
    }

    /// Test-only hook: drops the cached shell PATH so the next `detect`
    /// re-spawns the shell. Not used in production.
    static func resetShellPathCacheForTesting() {
        cachedShellPath = nil
    }

    private static var cachedShellPath: String?

    private static func resolveShellPath() -> String {
        let env = ProcessInfo.processInfo.environment
        let shell = env["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -i (interactive) sources .zshrc; -l (login) sources .zprofile.
        // Between them we get the same PATH the user sees when they open
        // a fresh Terminal window. The command stays a single-line echo
        // so we don't have to worry about rc-file output interleaving
        // with $PATH on stdout.
        process.arguments = ["-ilc", "printf '%s' \"$PATH\""]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let captured = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !captured.isEmpty {
                return captured
            }
        } catch {
            // Fall through to whatever the launching environment gave us.
        }
        return env["PATH"] ?? ""
    }
}

