import Foundation

/// A personal skill the user can offer (a real skill folder they authored, not
/// a managed/linked one).
struct ContributableSkill: Identifiable, Hashable {
    var id: URL { directory }
    let name: String
    let directory: URL
    /// Which tool's folder it was found in (for display).
    let tool: String
}

/// A file staged for the commit: its path in the repo and raw bytes.
struct PreparedFile: Equatable {
    let repoPath: String
    let content: Data
}

/// Result handed back to the UI.
struct ContributionResult: Equatable {
    let url: String
    let number: Int
}

enum ContributionError: LocalizedError, Equatable {
    case noRepoURL
    case badRepoURL(String)
    case noToken
    case nothingSelected
    case invalidName(String)
    case skillMissingManifest(String)
    case emptyContext(String)
    case fileTooLarge(path: String, size: Int, max: Int)
    case collision(kind: String, name: String)

    var errorDescription: String? {
        switch self {
        case .noRepoURL: return "Set a skills repo URL in Settings first."
        case .badRepoURL(let u): return "The skills repo URL is not a github.com repository: \(u)"
        case .noToken: return "Set a contributor GitHub token in Settings first."
        case .nothingSelected: return "Select at least one skill or context to contribute."
        case .invalidName(let n): return "'\(n)' is not a valid name for a repo folder."
        case .skillMissingManifest(let n): return "Skill '\(n)' has no SKILL.md."
        case .emptyContext(let n): return "'\(n)' has no recognized context files to contribute."
        case .fileTooLarge(let path, let size, let max):
            return "'\(path)' is \(size) bytes, over the \(max) byte limit."
        case .collision(let kind, let name):
            return "'\(kind)/\(name)' already exists in the repo — choose a different name (additions only)."
        }
    }
}

/// Propose additions (personal skills + project contexts) to the shared repo
/// as a pull request. Additions-only on branches in the one repo: gather the
/// selected files, create a single commit on a fresh branch off the default
/// branch, and open a PR. `main` is never modified directly (the repo's branch
/// ruleset enforces that) and we block additions whose target folder exists.
///
/// All GitHub I/O goes through `GitHubClient` so the choreography is testable
/// with a fake; pure helpers carry the bulk of the logic and the tests.
enum ContributionService {
    /// Files larger than this are refused — skills/contexts are text-ish; a big
    /// blob is almost certainly a mistake (or a secret) we don't want in the repo.
    static let maxFileBytes = 1024 * 1024

    // MARK: - Pure helpers

    /// Parses `(owner, repo)` from a github.com URL, tolerating a trailing
    /// `.git` and/or slash. Returns nil for non-github.com hosts.
    static func parseOwnerRepo(_ url: String) -> (owner: String, repo: String)? {
        var trimmed = url.trimmingCharacters(in: .whitespaces)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        let prefixes = ["https://github.com/", "http://github.com/", "git@github.com:"]
        guard let prefix = prefixes.first(where: { trimmed.hasPrefix($0) }) else { return nil }
        var rest = String(trimmed.dropFirst(prefix.count))
        if rest.hasSuffix(".git") { rest = String(rest.dropLast(4)) }
        let parts = rest.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        let owner = parts[0].trimmingCharacters(in: .whitespaces)
        let repo = parts[1].trimmingCharacters(in: .whitespaces)
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        return (owner, repo)
    }

    /// Sanitises a folder name: a single path segment of safe characters, no
    /// traversal, no leading dot.
    static func sanitizeName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let valid = !trimmed.isEmpty
            && !trimmed.hasPrefix(".")
            && !trimmed.contains("/")
            && !trimmed.contains("\\")
            && !trimmed.contains("..")
            && trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
        guard valid else { throw ContributionError.invalidName(name) }
        return trimmed
    }

    /// Personal skills across both tools: real skill folders (containing
    /// SKILL.md) that are NOT managed links. De-duplicated by name (first tool
    /// wins), sorted.
    static func enumeratePersonalSkills(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [ContributableSkill] {
        var seen: [String: ContributableSkill] = [:]
        for tool in SkillTool.allCases {
            let root = SkillsSyncService.skillsRoot(for: tool, home: home)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for dir in entries {
                let name = dir.lastPathComponent
                // Managed skills are symlinks — only offer real folders.
                if SkillsSyncService.isSymlink(dir, fileManager: fileManager) { continue }
                let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDir else { continue }
                guard fileManager.fileExists(atPath: dir.appendingPathComponent("SKILL.md").path) else { continue }
                if seen[name] == nil {
                    seen[name] = ContributableSkill(name: name, directory: dir, tool: tool.displayName)
                }
            }
        }
        return seen.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Stages every file under a skill folder as `skills/<name>/<relative>`.
    static func prepareSkillFiles(
        name: String, dir: URL, fileManager: FileManager = .default
    ) throws -> [PreparedFile] {
        guard fileManager.fileExists(atPath: dir.appendingPathComponent("SKILL.md").path) else {
            throw ContributionError.skillMissingManifest(name)
        }
        var files: [PreparedFile] = []
        let enumerator = fileManager.enumerator(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isFile else { continue }
            let relative = relativePath(of: url, under: dir)
            files.append(try read(url, repoPath: "skills/\(name)/\(relative)", fileManager: fileManager))
        }
        return files.sorted { $0.repoPath < $1.repoPath }
    }

    /// Stages only the recognized files of a context as `context/<name>/<file>`.
    static func prepareContextFiles(
        name: String, dir: URL, selected: [String], fileManager: FileManager = .default
    ) throws -> [PreparedFile] {
        var files: [PreparedFile] = []
        for file in CompanyContext.recognizedFileNames where selected.contains(file) {
            let path = dir.appendingPathComponent(file)
            guard fileManager.fileExists(atPath: path.path) else { continue }
            files.append(try read(path, repoPath: "context/\(name)/\(file)", fileManager: fileManager))
        }
        guard !files.isEmpty else { throw ContributionError.emptyContext(name) }
        return files
    }

    private static func relativePath(of url: URL, under base: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        let relative = urlComponents.dropFirst(baseComponents.count)
        return relative.joined(separator: "/")
    }

    private static func read(
        _ url: URL, repoPath: String, fileManager: FileManager
    ) throws -> PreparedFile {
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? Int) ?? 0
        guard size <= maxFileBytes else {
            throw ContributionError.fileTooLarge(path: repoPath, size: size, max: maxFileBytes)
        }
        let content = try Data(contentsOf: url)
        return PreparedFile(repoPath: repoPath, content: content)
    }

    static func buildBranchName(login: String, timestamp: String) -> String {
        let slug = String(login.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        return "contrib/\(slug.isEmpty ? "user" : slug)-\(timestamp)"
    }

    static func buildPRTitle(skills: [String], contexts: [String]) -> String {
        var parts: [String] = []
        if !skills.isEmpty { parts.append("skill(s): \(skills.joined(separator: ", "))") }
        if !contexts.isEmpty { parts.append("context(s): \(contexts.joined(separator: ", "))") }
        return "Add " + parts.joined(separator: "; ")
    }

    static func buildPRBody(skills: [String], contexts: [String], login: String) -> String {
        var lines = ["Proposed additions via BMad Manager.", ""]
        lines += skills.map { "- skill: `skills/\($0)/`" }
        lines += contexts.map { "- context: `context/\($0)/`" }
        lines.append("")
        lines.append("Submitted by @\(login).")
        return lines.joined(separator: "\n")
    }

    // MARK: - Orchestration

    struct SkillSelection { let name: String; let directory: URL }
    struct ContextSelection { let targetName: String; let directory: URL; let files: [String] }

    /// Stage the selected files, create a branch + single commit off the
    /// default branch, and open a PR. `timestamp` is injected so branch names
    /// are deterministic in tests.
    static func submitContribution(
        client: GitHubClient,
        owner: String,
        repo: String,
        skills: [SkillSelection],
        contexts: [ContextSelection],
        title: String?,
        timestamp: String,
        fileManager: FileManager = .default
    ) async throws -> ContributionResult {
        guard !skills.isEmpty || !contexts.isEmpty else { throw ContributionError.nothingSelected }

        var files: [PreparedFile] = []
        var skillNames: [String] = []
        for sel in skills {
            let name = try sanitizeName(sel.name)
            files += try prepareSkillFiles(name: name, dir: sel.directory, fileManager: fileManager)
            skillNames.append(name)
        }
        var contextNames: [String] = []
        for sel in contexts {
            let name = try sanitizeName(sel.targetName)
            files += try prepareContextFiles(
                name: name, dir: sel.directory, selected: sel.files, fileManager: fileManager)
            contextNames.append(name)
        }

        let login = try await client.whoami()
        let base = try await client.defaultBranch(owner: owner, repo: repo)

        for name in skillNames where try await client.pathExists(
            owner: owner, repo: repo, path: "skills/\(name)", branch: base) {
            throw ContributionError.collision(kind: "skills", name: name)
        }
        for name in contextNames where try await client.pathExists(
            owner: owner, repo: repo, path: "context/\(name)", branch: base) {
            throw ContributionError.collision(kind: "context", name: name)
        }

        let baseSHA = try await client.branchHeadSHA(owner: owner, repo: repo, branch: base)
        let baseTree = try await client.commitTreeSHA(owner: owner, repo: repo, commitSHA: baseSHA)

        var entries: [GitHubTreeEntry] = []
        for file in files {
            let blob = try await client.createBlob(
                owner: owner, repo: repo, contentBase64: file.content.base64EncodedString())
            entries.append(GitHubTreeEntry(path: file.repoPath, blobSHA: blob))
        }
        let tree = try await client.createTree(
            owner: owner, repo: repo, baseTree: baseTree, entries: entries)

        let resolvedTitle = title?.trimmingCharacters(in: .whitespaces)
        let prTitle = (resolvedTitle?.isEmpty == false)
            ? resolvedTitle!
            : buildPRTitle(skills: skillNames, contexts: contextNames)
        let commit = try await client.createCommit(
            owner: owner, repo: repo, message: prTitle, tree: tree, parent: baseSHA)

        let branch = buildBranchName(login: login, timestamp: timestamp)
        try await client.createBranchRef(owner: owner, repo: repo, branch: branch, sha: commit)

        let body = buildPRBody(skills: skillNames, contexts: contextNames, login: login)
        let pull = try await client.createPull(
            owner: owner, repo: repo, title: prTitle, head: branch, base: base, body: body)
        return ContributionResult(url: pull.htmlURL, number: pull.number)
    }
}
