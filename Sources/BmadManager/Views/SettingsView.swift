import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2).bold()

            VStack(alignment: .leading, spacing: 6) {
                Text("Projects root folder").font(.subheadline).bold()
                HStack {
                    TextField("", text: $store.settings.projectsRoot)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseFolder() }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Marketing growth module (.zip)").font(.subheadline).bold()
                HStack {
                    TextField("", text: $store.settings.moduleZipPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseZip() }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Init command").font(.subheadline).bold()
                TextEditor(text: $store.settings.initCommand)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.3))
                    )
                Text("Placeholders: {PROJECT_PATH}, {MODULE_PATH}, {PROJECT_NAME}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude Code command").font(.subheadline).bold()
                    TextField("", text: $store.settings.claudeCommand)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("opencode command").font(.subheadline).bold()
                    TextField("", text: $store.settings.opencodeCommand)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Spacer()

            HStack {
                Button("Reset to defaults", role: .destructive) {
                    showResetConfirm = true
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 540)
        .confirmationDialog(
            "Reset all settings to defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.projectsRoot = url.path
        }
    }

    private func chooseZip() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.moduleZipPath = url.path
        }
    }
}
