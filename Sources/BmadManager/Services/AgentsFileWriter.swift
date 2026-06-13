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
    static let sectionMarker = "<!-- bmad-manager:bmad start -->"
    static let endMarker = "<!-- bmad-manager:bmad end -->"

    /// The managed BMad block, start/end markers included.
    static func bmadBlock() -> String {
        """
        \(sectionMarker)
        # BMad

        - BMad skills are installed in `.agents/skills`.
        - Use `bmad-help` when the user asks for BMad help, workflow routing, next steps, or menu options.
        - BMad menu codes are defined in `_bmad/_config/bmad-help.csv`.
        - When the user enters a BMad menu code, look it up in `_bmad/_config/bmad-help.csv`, identify the `skill`, then use that skill.
        - When using a BMad skill, read its `SKILL.md` completely before acting.
        \(endMarker)
        """
    }

    /// Ensures the managed BMad block is present and current in
    /// `<projectURL>/AGENTS.md`: creates the file if absent, appends the
    /// block if the file exists without it, or refreshes the block in place
    /// if it's already there — leaving any surrounding user content intact.
    static func ensureBmadSection(
        in projectURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let url = projectURL.appendingPathComponent("AGENTS.md")
        let block = bmadBlock()

        guard fileManager.fileExists(atPath: url.path),
              let existing = try? String(contentsOf: url, encoding: .utf8)
        else {
            try (block + "\n").write(to: url, atomically: true, encoding: .utf8)
            return
        }

        if let start = existing.range(of: sectionMarker),
           let end = existing.range(of: endMarker, range: start.upperBound..<existing.endIndex) {
            // Refresh the managed block in place; leave user content around it.
            var updated = existing
            updated.replaceSubrange(start.lowerBound..<end.upperBound, with: block)
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
