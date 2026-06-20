import Foundation

/// Reads the two version sources behind "is this project behind the repo?":
/// the module repo's `skills/module.yaml` (`code` + `module_version`) and an
/// installed project's `_bmad/_config/manifest.yaml` (`modules[].version`),
/// and compares them with a leading-`v`-tolerant semver order.
///
/// The project ships no YAML parser, and we only need a couple of scalars and
/// one list scan, so the reads are hand-rolled line scans rather than a
/// dependency. The bias throughout is conservative: anything we can't read
/// cleanly is treated as "not stale" so we never show a false update badge.
enum ModuleManifest {
    /// The module's own identity, read from the repo's `skills/module.yaml`.
    /// `code` matches the installed manifest's `modules[].name`.
    struct RepoModule: Equatable {
        let code: String
        let version: String
    }

    /// Reads `<moduleRoot>/skills/module.yaml`. Returns nil if the file is
    /// absent or either top-level scalar (`code`, `module_version`) is missing.
    static func readRepoModule(atModuleRoot moduleRoot: URL) -> RepoModule? {
        let url = moduleRoot.appendingPathComponent("skills/module.yaml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var code: String?
        var version: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            // Only top-level (column-0) keys count, so a `module_version:`
            // nested under another block can't be mistaken for the real one.
            guard let first = line.first, first != " ", first != "\t" else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") { continue }
            if code == nil, let value = scalar(in: trimmed, key: "code") { code = value }
            if version == nil, let value = scalar(in: trimmed, key: "module_version") { version = value }
            if code != nil && version != nil { break }
        }

        guard let code, let version, !code.isEmpty, !version.isEmpty else { return nil }
        return RepoModule(code: code, version: version)
    }

    /// Reads the installed version of `moduleCode` from a project's
    /// `_bmad/_config/manifest.yaml` — a YAML list of `{name, version, …}`
    /// mappings under `modules:`. Returns the raw value (no `v`-strip) or nil
    /// if the manifest is missing/unreadable or lists no such module.
    static func installedVersion(ofModule moduleCode: String, inProject projectURL: URL) -> String? {
        let url = projectURL.appendingPathComponent("_bmad/_config/manifest.yaml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var inModules = false
        var currentName: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let isTopLevel = !(line.first == " " || line.first == "\t")
            if isTopLevel {
                // A column-0 key — we're inside `modules:` only while it's the
                // active block (so `installation.version` can't leak in).
                inModules = trimmed.hasPrefix("modules:")
                currentName = nil
                continue
            }

            guard inModules else { continue }
            if trimmed.hasPrefix("- ") {
                let item = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                currentName = scalar(in: item, key: "name")
            } else if currentName == moduleCode, let version = scalar(in: trimmed, key: "version") {
                return version
            }
        }
        return nil
    }

    /// True iff `lhs` is a strictly older version than `rhs`. Strips a leading
    /// `v`/`V`, splits on `.`, and compares components numerically (missing or
    /// non-numeric components count as 0).
    static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        let l = numericComponents(lhs)
        let r = numericComponents(rhs)
        for i in 0..<max(l.count, r.count) {
            let lv = i < l.count ? l[i] : 0
            let rv = i < r.count ? r[i] : 0
            if lv != rv { return lv < rv }
        }
        return false
    }

    /// True iff the project has `repoModule` installed at a strictly older
    /// version. nil/unreadable/unparseable installed versions are treated as
    /// "not stale" so we never badge a project we can't actually compare.
    static func isProjectStale(projectURL: URL, repoModule: RepoModule) -> Bool {
        guard let installed = installedVersion(ofModule: repoModule.code, inProject: projectURL) else {
            return false
        }
        guard hasNumericComponent(installed), hasNumericComponent(repoModule.version) else {
            return false
        }
        return isOlder(installed, than: repoModule.version)
    }

    // MARK: - Parsing helpers

    /// Returns the value of a `key: value` scalar on a single trimmed line,
    /// or nil if the line isn't that key. Surrounding quotes are stripped.
    private static func scalar(in line: String, key: String) -> String? {
        guard line.hasPrefix(key) else { return nil }
        let afterKey = line.dropFirst(key.count)
        guard afterKey.first == ":" else { return nil }
        return unquote(afterKey.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last else { return value }
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func numericComponents(_ version: String) -> [Int] {
        return strippedVersion(version)
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }

    private static func hasNumericComponent(_ version: String) -> Bool {
        return strippedVersion(version)
            .split(separator: ".")
            .contains { Int($0.trimmingCharacters(in: .whitespaces)) != nil }
    }

    private static func strippedVersion(_ version: String) -> String {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return v
    }
}
