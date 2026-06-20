import SwiftUI

struct ProjectRowView: View {
    let project: ProjectItem
    /// True when the project's installed module version is behind the repo's
    /// latest — surfaces the Update button. Purely presentational: the row
    /// branches on this flag but doesn't compute it.
    var updateAvailable: Bool = false
    let onClaude: () -> Void
    let onOpencode: () -> Void
    let onPi: () -> Void
    let onCodex: () -> Void
    let onOpenFolder: () -> Void
    var onUpdate: () -> Void = {}
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let createdAt = project.createdAt {
                    Text("Created \(createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // Shown only when the project is behind the latest module version.
            if updateAvailable {
                Button("Update", action: onUpdate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Re-install the latest module and refresh AGENTS.md")
                    .accessibilityLabel("Update project")
            }
            // Agent launch buttons, ordered alphabetically by label.
            Button("Claude Code", action: onClaude)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Codex", action: onCodex)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("opencode", action: onOpencode)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Pi", action: onPi)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(action: onOpenFolder) {
                Image(systemName: "folder.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open project folder in Finder")
            .accessibilityLabel("Open Folder")
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Move to Trash")
            .accessibilityLabel("Move to Trash")
        }
        .padding(.vertical, 2)
    }
}
