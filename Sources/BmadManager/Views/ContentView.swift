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
                .onDisappear { refreshProjects() }
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
        .onAppear { refreshProjects() }
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

    private var header: some View {
        HStack {
            Text("BMad Manager")
                .font(.headline)
            Spacer()
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

        // If the user is on local-zip and hasn't picked a module yet,
        // prompt for one and persist the choice before kicking off
        // creation. Centralising the prompt here keeps the coordinator
        // free of UI concerns and avoids the @StateObject-drift bug
        // that captured-SettingsStore reads used to expose.
        if settings.settings.moduleSourceKind == .localZip,
           settings.settings.moduleZipPath.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let picked = promptForModuleZip() else {
                coordinator.errorMessage = "A marketing growth module .zip is required to create a project."
                return
            }
            settings.settings.moduleZipPath = picked.path
        }

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
