import Foundation

/// Writes the project `AGENTS.md` that wires the BMad install up for Codex.
///
/// Codex *discovers* the BMad skills fine — it auto-loads repo-scoped skills
/// from `.agents/skills/` (CWD, parent dirs, repo root). What it can't infer
/// is BMad's *routing*: that short menu codes (BH, PRD, DS, …) map to skills
/// through `_bmad/_config/bmad-help.csv`, and that `bmad-help` is the entry
/// point. bmad-method installs the skills but emits no Codex `AGENTS.md`
/// (unlike claude-code's native `.claude/skills` or opencode's
/// `.opencode/commands` pointers), so bmad-manager writes one here.
///
/// The managed block is delimited by start/end markers, so it can be created
/// fresh, appended to a user's existing `AGENTS.md`, or refreshed in place on
/// a later re-install — without disturbing anything the user wrote around it.
enum AgentsFileWriter {
    /// The bmad-manager block's start marker, preserved as the public contract
    /// other call sites and tests pin. Equals `startMarker(for:)` of the bmad
    /// namespace (verified by a test, so the two can't drift).
    static let sectionMarker = "<!-- bmad-manager:bmad start -->"

    private static let bmadNamespace = "bmad-manager:bmad"

    /// The marker pair for a namespace token (e.g. `bmad-manager:bmad`,
    /// `marketing-growth:okf`). HTML comments, so they're invisible in rendered
    /// Markdown; each namespace gets its own pair, so blocks never collide.
    static func startMarker(for namespace: String) -> String { "<!-- \(namespace) start -->" }
    static func endMarker(for namespace: String) -> String { "<!-- \(namespace) end -->" }

    /// The managed BMad block, start/end markers included.
    static func bmadBlock() -> String {
        wrap(namespace: bmadNamespace, body: bmadBody())
    }

    /// The BMad body, without markers — the core wraps it.
    private static func bmadBody() -> String {
        """
        # BMad

        - BMad skills are installed in `.agents/skills`.
        - Use `bmad-help` when the user asks for BMad help, workflow routing, next steps, or menu options.
        - BMad menu codes are defined in `_bmad/_config/bmad-help.csv`.
        - When the user enters a BMad menu code, look it up in `_bmad/_config/bmad-help.csv`, identify the `skill`, then use that skill.
        - When using a BMad skill, read its `SKILL.md` completely before acting.
        """
    }

    /// Wraps a marker-free `body` in the namespace's start/end markers.
    private static func wrap(namespace: String, body: String) -> String {
        "\(startMarker(for: namespace))\n\(body)\n\(endMarker(for: namespace))"
    }

    /// Ensures the managed BMad block is present and current in
    /// `<projectURL>/AGENTS.md`. Thin wrapper over `ensureManagedSection`.
    static func ensureBmadSection(
        in projectURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try ensureManagedSection(
            in: projectURL, namespace: bmadNamespace, body: bmadBody(), fileManager: fileManager)
    }

    /// Ensures a managed block for `namespace` with the supplied marker-free
    /// `body` is present and current in `<projectURL>/<fileName>`: creates the
    /// file if absent, appends the block if the file exists without it, or
    /// refreshes the block in place if it's already there — leaving any
    /// surrounding user content (and other namespaces' blocks) intact.
    static func ensureManagedSection(
        in projectURL: URL,
        fileName: String = "AGENTS.md",
        namespace: String,
        body: String,
        fileManager: FileManager = .default
    ) throws {
        let url = projectURL.appendingPathComponent(fileName)
        let start = startMarker(for: namespace)
        let end = endMarker(for: namespace)
        let block = wrap(namespace: namespace, body: body)

        guard fileManager.fileExists(atPath: url.path),
              let existing = try? String(contentsOf: url, encoding: .utf8)
        else {
            try (block + "\n").write(to: url, atomically: true, encoding: .utf8)
            return
        }

        if let startRange = existing.range(of: start),
           let endRange = existing.range(of: end, range: startRange.upperBound..<existing.endIndex) {
            // Refresh this namespace's block in place; leave everything else alone.
            var updated = existing
            updated.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: block)
            if updated != existing {
                try updated.write(to: url, atomically: true, encoding: .utf8)
            }
        } else {
            // Append, preserving the user's existing content.
            let separator = existing.hasSuffix("\n") ? "\n" : "\n\n"
            try (existing + separator + block + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
