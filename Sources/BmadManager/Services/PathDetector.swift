import Foundation
import Darwin

/// Resolves a coding-agent command (e.g. `claude`, `opencode`, `pi`) to
/// an absolute file path. The Settings dialog calls this so the user
/// knows whether the bare-name defaults are reachable before they need
/// to browse for a binary.
///
/// Behaviour:
///   * Bare names are looked up under every entry of the user's login-
///     shell PATH; only entries that point at a regular file with at
///     least one execute bit set count.
///   * A command containing `/` is treated as an explicit absolute or
///     relative path and checked directly — no PATH lookup, no
///     executable-bit check, because the user pointed at it on purpose.
///   * Empty/whitespace-only input always returns `nil`.
///
/// Why we don't use `FileManager.isExecutableFile(atPath:)`: that
/// wrapper calls `access(X_OK)`, which on macOS can refuse binaries
/// carrying a `com.apple.quarantine` xattr — e.g. the `opencode` build
/// distributed by https://opencode.ai/install lands under
/// `~/.opencode/bin` with quarantine set and trips this even though the
/// chmod bits are `-rwxr-xr-x`. A stat-based check (regular file + any
/// execute bit) gives the same answer the user's shell does at
/// resolution time; Gatekeeper still gets the last word at `exec(2)`.
///
/// Why we strip non-absolute PATH entries: rc files commonly echo
/// banner text to stdout before our PATH-capture `printf` runs
/// (Python virtualenv reminders, p10k instant-prompt warnings,
/// oh-my-zsh updates). Splitting the captured output on `:` then turns
/// those banners into fake PATH "entries" that we'd otherwise probe.
/// Real PATH entries are absolute, so anything not starting with `/`
/// can be skipped.
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
            guard dir.hasPrefix("/") else { continue }
            let candidate = (dir as NSString).appendingPathComponent(trimmed)
            if isLikelyExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Returns the PATH the user's interactive login shell exports,
    /// captured once per app run. Spawning a shell on every keystroke
    /// would be wasteful, and a user editing `~/.zshrc` mid-session can
    /// relaunch the app to pick the new PATH up.
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

    /// Extracts the PATH from a shell-captured printf payload wrapped
    /// in `BMAD_PATH_START` / `BMAD_PATH_END` markers. Returns nil if
    /// the markers aren't present (in which case the caller falls back
    /// to whatever PATH the launching process inherited).
    static func parseShellPathOutput(_ raw: String) -> String? {
        let opener = "\(pathStartMarker)\n"
        let closer = "\n\(pathEndMarker)"
        guard let startRange = raw.range(of: opener),
              let endRange = raw.range(
                of: closer,
                range: startRange.upperBound..<raw.endIndex
              )
        else { return nil }
        return String(raw[startRange.upperBound..<endRange.lowerBound])
    }

    private static var cachedShellPath: String?
    private static let pathStartMarker = "BMAD_PATH_START"
    private static let pathEndMarker = "BMAD_PATH_END"

    private static func resolveShellPath() -> String {
        let env = ProcessInfo.processInfo.environment
        let shell = env["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -i (interactive) sources .zshrc; -l (login) sources
        // .zprofile / .zlogin. Between them we get the same PATH a
        // fresh Terminal window sees. The printf is wrapped in
        // BMAD_PATH_START / BMAD_PATH_END markers so we can strip any
        // banner text rc files printed before our line ran.
        let cmd = #"printf '\n\#(pathStartMarker)\n%s\n\#(pathEndMarker)\n' "$PATH""#
        process.arguments = ["-ilc", cmd]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8) ?? ""
            if let extracted = parseShellPathOutput(raw), !extracted.isEmpty {
                return extracted
            }
        } catch {
            // Fall through to whatever the launching environment gave us.
        }
        return env["PATH"] ?? ""
    }

    private static func isLikelyExecutable(_ path: String) -> Bool {
        var st = stat()
        guard stat(path, &st) == 0 else { return false }
        let isRegular = (st.st_mode & S_IFMT) == S_IFREG
        let hasAnyExec = (st.st_mode & mode_t(0o111)) != 0
        return isRegular && hasAnyExec
    }
}
