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
    @State private var codexDetected: String? = nil

    // Whether each agent's desktop app is installed. Drives the App-vs-CLI
    // launch picker captions and is detected once when the sheet opens,
    // for the same reason the terminal list is.
    @State private var claudeAppInstalled: Bool = false
    @State private var codexAppInstalled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.title2).bold()

            ScrollView {
                form
                    .padding(.trailing, 4) // breathing room for the scroller
            }

            Divider()

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
        .onChange(of: store.settings.codexCommand) {
            codexDetected = PathDetector.detect(store.settings.codexCommand)
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

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    detected: claudeDetected,
                    launchMethod: $store.settings.claudeLaunchMethod,
                    appName: AgentApp.claude.appDisplayName,
                    appNote: AgentApp.claude.appLaunchNote,
                    appInstalled: claudeAppInstalled
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
                agentRow(
                    label: "Codex",
                    text: $store.settings.codexCommand,
                    detected: codexDetected,
                    launchMethod: $store.settings.codexLaunchMethod,
                    appName: AgentApp.codex.appDisplayName,
                    appNote: AgentApp.codex.appLaunchNote,
                    appInstalled: codexAppInstalled
                ) {
                    if let picked = browseForExecutable(label: "Codex") {
                        store.settings.codexCommand = picked
                    }
                }
            }
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
        codexDetected    = PathDetector.detect(store.settings.codexCommand)
        claudeAppInstalled = AppDetector.isInstalled(.claude)
        codexAppInstalled  = AppDetector.isInstalled(.codex)
    }

    @ViewBuilder
    private func agentRow(
        label: String,
        text: Binding<String>,
        detected: String?,
        launchMethod: Binding<AgentLaunchMethod>? = nil,
        appName: String? = nil,
        appNote: String = "",
        appInstalled: Bool = false,
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

            if let launchMethod {
                launchMethodControl(
                    appName: appName ?? label,
                    appNote: appNote,
                    selection: launchMethod,
                    appInstalled: appInstalled
                )
            }
        }
    }

    /// The App-vs-CLI launch picker shown under agents that also ship a
    /// macOS desktop app (Claude, Codex). `Auto` prefers the app when it's
    /// installed and otherwise runs the CLI; `App`/`CLI` force one path.
    @ViewBuilder
    private func launchMethodControl(
        appName: String,
        appNote: String,
        selection: Binding<AgentLaunchMethod>,
        appInstalled: Bool
    ) -> some View {
        Text("Launch with").font(.subheadline).bold()
            .padding(.top, 2)
        Picker("Launch with", selection: selection) {
            ForEach(AgentLaunchMethod.allCases) { method in
                Text(method.displayName).tag(method)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        if appInstalled {
            Text("\(appName) app detected. \(appNote) CLI runs the command above in the terminal.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("\(appName) app not installed. Auto uses the command above; choose App only once it's installed.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
