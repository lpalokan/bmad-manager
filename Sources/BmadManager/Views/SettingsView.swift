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
                Text("Marketing growth module source").font(.subheadline).bold()
                Picker("Source", selection: $store.settings.moduleSourceKind) {
                    ForEach(ModuleSourceKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch store.settings.moduleSourceKind {
                case .gitRepo:
                    TextField("GitHub repo URL", text: $store.settings.moduleRepoURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Branch, tag, or SHA (blank = default branch)",
                              text: $store.settings.moduleRepoRef)
                        .textFieldStyle(.roundedBorder)
                    Text("Requires git on PATH (Xcode Command Line Tools provides it).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .localZip:
                    HStack {
                        TextField("Path to .zip", text: $store.settings.moduleZipPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") { chooseZip() }
                    }
                    Text("GitHub \"Download ZIP\" archives are unwrapped automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .frame(width: 620, height: 620)
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
