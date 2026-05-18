import SwiftUI

struct ProjectRowView: View {
    let project: ProjectItem
    let onClaude: () -> Void
    let onOpencode: () -> Void
    let onOpenFolder: () -> Void
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
            Button("Claude Code", action: onClaude)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(action: onOpenFolder) {
                Label("Open Folder", systemImage: "folder.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open project folder in Finder")
            Button("opencode", action: onOpencode)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Move to Trash")
        }
        .padding(.vertical, 2)
    }
}
