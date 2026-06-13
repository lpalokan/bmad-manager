import Foundation

/// The coding tools that expose a global skills folder we can sync into.
enum SkillTool: CaseIterable {
    case claudeCode
    case codex

    /// The dotfolder under the user's home (`.claude` / `.codex`).
    var homeSubdir: String {
        switch self {
        case .claudeCode: return ".claude"
        case .codex:      return ".codex"
        }
    }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        }
    }
}

enum SkillsSyncError: LocalizedError {
    case noRepoURL
    case noToken
    case gitFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .noRepoURL: return "Set a skills repo URL in Settings first."
        case .noToken:   return "Set a GitHub token in Settings first."
        case .gitFailed(let code): return "git exited with code \(code). See the output panel."
        }
    }
}

/// Clones/updates a private GitHub skills repo into the per-tool `managed/`
/// skills folder. The `managed/` subfolder is owned entirely by the sync —
/// it is hard-reset to the remote tip on every run, so hand edits there are
/// discarded. Personal skills directly under `~/.claude/skills` /
/// `~/.codex/skills` (NOT under `managed/`) are never touched.
///
/// Builders are pure (unit-tested); `sync` takes an injected `runCommand` and
/// `FileManager` so the clone-vs-update orchestration is testable without a
/// real git or Keychain.
enum SkillsSyncService {
    /// `<home>/.claude/skills/managed` (or `.codex`). Pure.
    static func managedDirectory(for tool: SkillTool, home: URL) -> URL {
        home.appendingPathComponent(tool.homeSubdir, isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("managed", isDirectory: true)
    }

    /// The `Authorization` header git should send for `token`. Passed via
    /// `-c http.extraHeader=...` so the token never lands in `.git/config`
    /// or the remote URL. GitHub accepts any username with the PAT as the
    /// password; `x-access-token` matches the header GitHub Actions injects.
    static func authHeader(token: String) -> String {
        let creds = "x-access-token:\(token)"
        return "AUTHORIZATION: basic \(Data(creds.utf8).base64EncodedString())"
    }

    /// Shell command that clones the repo fresh into `dest`.
    static func cloneCommand(repoURL: String, branch: String, dest: URL, header: String) -> String {
        [
            "git",
            "-c", shellQuote("http.extraHeader=\(header)"),
            "clone", "--depth", "1", "--single-branch",
            "--branch", shellQuote(branch),
            shellQuote(repoURL),
            shellQuote(dest.path),
        ].joined(separator: " ")
    }

    /// Shell command (run with cwd = managed dir) that hard-updates an
    /// existing clone to the latest tip. `FETCH_HEAD` (not `origin/<branch>`)
    /// so it works even if the configured branch changed since the clone.
    static func updateCommand(branch: String, header: String) -> String {
        let fetch = [
            "git",
            "-c", shellQuote("http.extraHeader=\(header)"),
            "fetch", "--depth", "1", "origin", shellQuote(branch),
        ].joined(separator: " ")
        return "\(fetch) && git reset --hard FETCH_HEAD"
    }

    /// POSIX single-quote quoting (end-quote / escape / re-open) — mirrors
    /// `TerminalLauncher`'s quoting so interpolated paths/branches reach zsh
    /// verbatim.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Clone or hard-update the skills repo for `tool`, running git via
    /// `runCommand` (which streams output into the command panel). Throws on
    /// missing config or a non-zero git exit.
    static func sync(
        tool: SkillTool,
        repoURL: String,
        branch: String,
        token: String,
        home: URL,
        fileManager: FileManager = .default,
        runCommand: (String, URL) async -> Int32
    ) async throws {
        let trimmedURL = repoURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else { throw SkillsSyncError.noRepoURL }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw SkillsSyncError.noToken }

        let trimmedBranch = branch.trimmingCharacters(in: .whitespaces)
        let resolvedBranch = trimmedBranch.isEmpty ? "main" : trimmedBranch
        let header = authHeader(token: trimmedToken)
        let managed = managedDirectory(for: tool, home: home)

        var isDir: ObjCBool = false
        let gitDir = managed.appendingPathComponent(".git", isDirectory: true)
        let isRepo = fileManager.fileExists(atPath: gitDir.path, isDirectory: &isDir) && isDir.boolValue

        let exit: Int32
        if isRepo {
            exit = await runCommand(updateCommand(branch: resolvedBranch, header: header), managed)
        } else {
            // The managed dir is sync-owned: clear any leftover (non-repo)
            // contents so the clone has a clean destination, then ensure the
            // parent exists and clone into it.
            if fileManager.fileExists(atPath: managed.path) {
                try fileManager.removeItem(at: managed)
            }
            let parent = managed.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let command = cloneCommand(
                repoURL: trimmedURL,
                branch: resolvedBranch,
                dest: managed,
                header: header
            )
            exit = await runCommand(command, parent)
        }

        if exit != 0 { throw SkillsSyncError.gitFailed(exit) }
    }
}
