import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false

    // Detected once when the sheet opens — re-querying LaunchServices on
    // every redraw is wasteful, and a user installing a new terminal mid-
    // session can just reopen Settings.
    @State private var installedTerminals: [TerminalKind] = TerminalDetector.installedKinds()

    // PATH-detection results for the three coding-agent commands. `nil`
    // means "not found"; a string is the resolved absolute path. The
    // dictionary is re-computed whenever the user edits the relevant
    // command field so they get immediate feedback after typing.
    @State private var claudeDetected: String? = nil
    @State private var opencodeDetected: String? = nil
    @State private var piDetected: String? = nil

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

            VStack(alignment: .leading, spacing: 6) {
                Text("Terminal").font(.subheadline).bold()
                Picker("Terminal", selection: $store.settings.terminalKind) {
                    ForEach(installedTerminals) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(installedTerminals.count <= 1)
                Text("Only terminals installed on this Mac are shown. Install another supported terminal to add it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                agentRow(
                    label: "Claude Code",
                    text: $store.settings.claudeCommand,
                    detected: claudeDetected
                ) {
                    if let picked = browseForExecutable(label: "Claude Code") {
                        store.settings.claudeCommand = picked
                    }
                }
                agentRow(
                    label: "opencode",
                    text: $store.settings.opencodeCommand,
                    detected: opencodeDetected
                ) {
                    if let picked = browseForExecutable(label: "opencode") {
                        store.settings.opencodeCommand = picked
                    }
                }
                agentRow(
                    label: "Pi",
                    text: $store.settings.piCommand,
                    detected: piDetected
                ) {
                    if let picked = browseForExecutable(label: "Pi") {
                        store.settings.piCommand = picked
                    }
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
        .frame(width: 620, height: 720)
        .onAppear {
            reconcileTerminalSelection()
            refreshAgentDetection()
        }
        .onChange(of: store.settings.claudeCommand) {
            claudeDetected = PathDetector.detect(store.settings.claudeCommand)
        }
        .onChange(of: store.settings.opencodeCommand) {
            opencodeDetected = PathDetector.detect(store.settings.opencodeCommand)
        }
        .onChange(of: store.settings.piCommand) {
            piDetected = PathDetector.detect(store.settings.piCommand)
        }
        .confirmationDialog(
            "Reset all settings to defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// If the persisted terminal kind isn't installed (e.g. the user
    /// uninstalled iTerm2 after picking it), fall back to the first
    /// installed kind so the Picker has a matching tag and the launch
    /// path doesn't fail later. Terminal.app ships with macOS, so
    /// `installedTerminals` should never actually be empty — the
    /// fallback case is a defensive belt.
    private func reconcileTerminalSelection() {
        guard !installedTerminals.isEmpty else { return }
        if !installedTerminals.contains(store.settings.terminalKind) {
            store.settings.terminalKind = installedTerminals.first ?? .fallback
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

    private func browseForExecutable(label: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.title = "Choose \(label) executable"
        panel.prompt = "Use This Binary"
        panel.message = "Pick the \(label) executable. Most installs live under /usr/local/bin or /opt/homebrew/bin."
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func refreshAgentDetection() {
        claudeDetected   = PathDetector.detect(store.settings.claudeCommand)
        opencodeDetected = PathDetector.detect(store.settings.opencodeCommand)
        piDetected       = PathDetector.detect(store.settings.piCommand)
    }

    @ViewBuilder
    private func agentRow(
        label: String,
        text: Binding<String>,
        detected: String?,
        browse: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label) command").font(.subheadline).bold()
            HStack {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…", action: browse)
            }
            if let path = detected {
                Text("Detected at \(path)")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Not found on PATH. Use Browse… to point at the binary.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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
