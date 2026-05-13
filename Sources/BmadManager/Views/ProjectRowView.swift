import SwiftUI

struct ProjectRowView: View {
    let project: ProjectItem
    let onClaude: () -> Void
    let onOpencode: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(project.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button("Claude Code", action: onClaude)
                .buttonStyle(.bordered)
                .controlSize(.small)
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
