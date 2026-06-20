import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Thin adapter that binds `ProjectCoordinator` to SwiftUI views.
/// All project-lifecycle logic lives in the coordinator so it can be
/// tested without XCUITest.
struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var commandRunner: CommandRunner
    @EnvironmentObject var coordinator: ProjectCoordinator

    @State private var newProjectName: String = ""
    @State private var selectedContext: CompanyContext? = nil
    @State private var showSettings: Bool = false
    @State private var showContribute: Bool = false
    @State private var isSyncingSkills: Bool = false

    /// Reads the skills-repo token from the Keychain at click time. Kept here
    /// (not in the coordinator) so the coordinator stays Keychain-free.
    private let tokenStore: any TokenStore = KeychainTokenStore()

    var body: some View {
        VStack(spacing: 0) {
            header
            createRow
            if !coordinator.availableContexts.isEmpty {
                contextRow
            }
            sortRow
            Divider()

            if coordinator.projects.isEmpty {
                emptyState
            } else {
                projectList
            }

            Divider()
            skillsRow

            if coordinator.showOutput || commandRunner.isRunning {
                Divider()
                CommandOutputView()
                    .frame(height: 200)
            }
        }
        .padding(.top, 8)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                // Re-sync after Settings closes: a newly configured skills
                // repo (or token) should pull contexts/skills right away.
                .onDisappear { refreshAll() }
        }
        .sheet(isPresented: $showContribute) {
            ContributeView(
                settings: settings.settings,
                // GitHub-sourced contexts are already in the repo; only offer
                // the user's own project contexts.
                projectContexts: coordinator.availableContexts.filter { $0.source == .project },
                onClose: { showContribute = false }
            )
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { if !$0 { coordinator.errorMessage = nil } }
            )
        ) {
            Button("OK") { coordinator.errorMessage = nil }
        } message: {
            Text(coordinator.errorMessage ?? "")
        }
        .confirmationDialog(
            coordinator.projectToDelete.map { "Move '\($0.name)' to the Trash?" } ?? "Move to Trash?",
            isPresented: Binding(
                get: { coordinator.projectToDelete != nil },
                set: { if !$0 { coordinator.projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let project = coordinator.projectToDelete {
                Button("Move to Trash", role: .destructive) {
                    Task {
                        await coordinator.deleteProject(
                            project,
                            root: settings.settings.projectsRoot,
                            sortOrder: settings.settings.projectSortOrder
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { refreshAll() }
        .onChange(of: settings.settings.projectsRoot) { refreshProjects() }
        .onChange(of: settings.settings.projectSortOrder) { refreshProjects() }
        .onChange(of: coordinator.availableContexts) {
            // The selected source project may have been deleted or its
            // context removed since the last scan — fall back to scratch
            // rather than importing from a stale snapshot.
            if let selected = selectedContext,
               !coordinator.availableContexts.contains(selected) {
                selectedContext = nil
            }
        }
    }

    private func refreshProjects() {
        coordinator.refresh(
            root: settings.settings.projectsRoot,
            sortOrder: settings.settings.projectSortOrder
        )
    }

    /// Refreshes the local list immediately, then auto-syncs the shared
    /// skills repo (skills + `context/`) in the background and refreshes
    /// again so freshly-pulled GitHub contexts appear.
    private func refreshAll() {
        refreshProjects()
        Task { await autoSyncRepo() }
    }

    private func autoSyncRepo() async {
        await coordinator.syncSkillsRepo(
            settings: settings.settings,
            token: tokenStore.loadToken(),
            runCommand: { command, cwd in
                await commandRunner.run(command: command, cwd: cwd)
            }
        )
    }

    private var header: some View {
        HStack {
            Text("BMad Manager")
                .font(.headline)
            Spacer()
            Button {
                refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh projects and sync the skills repo")
            .buttonStyle(.plain)

            Button {
                coordinator.showOutput.toggle()
            } label: {
                Image(systemName: coordinator.showOutput ? "terminal.fill" : "terminal")
            }
            .help(coordinator.showOutput ? "Hide output" : "Show output")
            .buttonStyle(.plain)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var createRow: some View {
        HStack {
            TextField("New project name", text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if canCreate { Task { await createProject() } }
                }
            Button {
                Task { await createProject() }
            } label: {
                if coordinator.isCreating {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Create new project")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreate)
            Button("Initialize existing folder…") {
                Task { await initializeExistingFolder() }
            }
            .help("Run BMAD init in a folder that already exists")
            .disabled(coordinator.isCreating)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var canCreate: Bool {
        !coordinator.isCreating && !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Shown only when at least one existing project carries a company
    /// context the new project could be seeded from.
    private var contextRow: some View {
        HStack(spacing: 6) {
            Text("Context")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Context", selection: $selectedContext) {
                Text("Start from scratch").tag(nil as CompanyContext?)
                ForEach(coordinator.availableContexts) { context in
                    Text(context.displayName).tag(Optional(context))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Seed the new project's company context from an existing project")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var sortRow: some View {
        HStack(spacing: 6) {
            Text("Sort")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Sort", selection: $settings.settings.projectSortOrder) {
                ForEach(ProjectSortOrder.allCases, id: \.self) { order in
                    Text(order.displayName).tag(order)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    /// "Sync to Claude Code / Codex" buttons. Independent — a user clicks
    /// only the one for their tool. Disabled until a skills repo URL is set.
    private var skillsRow: some View {
        let noRepo = settings.settings.skillsRepoURL
            .trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 6) {
            Text("Skills")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Sync to Claude Code") {
                Task { await syncSkills(.claudeCode) }
            }
            .disabled(isSyncingSkills || coordinator.isCreating || noRepo)
            Button("Sync to Codex") {
                Task { await syncSkills(.codex) }
            }
            .disabled(isSyncingSkills || coordinator.isCreating || noRepo)
            Button("Contribute…") {
                showContribute = true
            }
            .disabled(coordinator.isCreating || noRepo)
            if isSyncingSkills {
                ProgressView().controlSize(.small)
            }
            if noRepo {
                Text("Set a skills repo URL in Settings to enable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Spacer()
            Text("No projects yet.")
                .foregroundStyle(.secondary)
            Text("Type a name above and click Create new project.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var projectList: some View {
        List(coordinator.projects) { project in
            ProjectRowView(
                project: project,
                onClaude: {
                    coordinator.openAgent(
                        project: project,
                        agent: .claude,
                        method: settings.settings.claudeLaunchMethod,
                        appInstalled: AppDetector.isInstalled(.claude),
                        command: settings.settings.claudeCommand,
                        kind: settings.settings.terminalKind
                    )
                },
                onOpencode: {
                    coordinator.openInTerminal(
                        project: project,
                        command: settings.settings.opencodeCommand,
                        kind: settings.settings.terminalKind
                    )
                },
                onPi: {
                    coordinator.openInTerminal(
                        project: project,
                        command: settings.settings.piCommand,
                        kind: settings.settings.terminalKind
                    )
                },
                onCodex: {
                    coordinator.openAgent(
                        project: project,
                        agent: .codex,
                        method: settings.settings.codexLaunchMethod,
                        appInstalled: AppDetector.isInstalled(.codex),
                        command: settings.settings.codexCommand,
                        kind: settings.settings.terminalKind
                    )
                },
                onOpenFolder: { coordinator.openProjectFolder(project) },
                onDelete: { coordinator.projectToDelete = project }
            )
        }
    }

    // MARK: - Actions

    private func createProject() async {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard ensureModuleZipIfNeeded() else { return }

        await coordinator.createProject(
            name: name,
            settings: settings.settings,
            importContextFrom: selectedContext,
            runCommand: { command, cwd in
                await commandRunner.run(command: command, cwd: cwd)
            }
        )

        if coordinator.errorMessage == nil {
            newProjectName = ""
            // Reset to scratch so the next creation doesn't silently
            // inherit the previous selection.
            selectedContext = nil
        }
    }

    /// "Initialize existing folder…": pick any folder, then run BMAD init in
    /// it (cwd = that folder, name = its basename). A non-empty folder gets a
    /// destructive-overwrite confirmation before proceeding; an empty one runs
    /// silently. A detected existing BMAD install is flagged more strongly.
    private func initializeExistingFolder() async {
        guard let folder = promptForExistingFolder() else { return }

        let service = ProjectService()
        if !service.folderIsEmpty(folder) {
            let isInstall = service.folderHasBmadInstall(folder)
            guard confirmInitInNonEmptyFolder(folder, existingInstall: isInstall) else { return }
        }
        guard ensureModuleZipIfNeeded() else { return }

        await coordinator.createProject(
            name: folder.lastPathComponent,
            settings: settings.settings,
            importContextFrom: selectedContext,
            destination: folder,
            runCommand: { command, cwd in
                await commandRunner.run(command: command, cwd: cwd)
            }
        )

        if coordinator.errorMessage == nil {
            selectedContext = nil
        }
    }

    /// On local-zip, prompts for (and persists) a module .zip when one
    /// hasn't been chosen yet. Returns `false` (after setting an error) when
    /// the user cancels the prompt. Centralising it here keeps the
    /// coordinator free of UI concerns and avoids the @StateObject-drift bug
    /// that captured-SettingsStore reads used to expose. Shared by both the
    /// new-project and existing-folder flows.
    private func ensureModuleZipIfNeeded() -> Bool {
        guard settings.settings.moduleSourceKind == .localZip,
              settings.settings.moduleZipPath.trimmingCharacters(in: .whitespaces).isEmpty
        else { return true }
        guard let picked = promptForModuleZip() else {
            coordinator.errorMessage = "A marketing growth module .zip is required to create a project."
            return false
        }
        settings.settings.moduleZipPath = picked.path
        return true
    }

    private func promptForExistingFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose a folder to initialize"
        panel.prompt = "Initialize Here"
        panel.message = "Pick a folder to run BMAD init in. The project name is taken from the folder's name."
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func confirmInitInNonEmptyFolder(_ folder: URL, existingInstall: Bool) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if existingInstall {
            alert.messageText = "'\(folder.lastPathComponent)' already looks like a BMAD project."
            alert.informativeText = "Re-running init here may overwrite or modify the existing BMAD setup. Continue?"
        } else {
            alert.messageText = "'\(folder.lastPathComponent)' already contains files."
            alert.informativeText = "Initializing may overwrite or modify them. Continue?"
        }
        alert.addButton(withTitle: "Initialize")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func syncSkills(_ tool: SkillTool) async {
        guard !isSyncingSkills else { return }
        isSyncingSkills = true
        defer { isSyncingSkills = false }
        await coordinator.syncSkills(
            tool: tool,
            settings: settings.settings,
            token: tokenStore.loadToken(),
            runCommand: { command, cwd in
                await commandRunner.run(command: command, cwd: cwd)
            }
        )
    }

    private func promptForModuleZip() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        panel.title = "Select the marketing growth module"
        panel.prompt = "Use This Zip"
        panel.message = "Pick the marketing growth module .zip — it will be remembered for future projects."
        return panel.runModal() == .OK ? panel.url : nil
    }
}
