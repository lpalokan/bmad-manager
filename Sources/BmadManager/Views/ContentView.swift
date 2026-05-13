import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var commandRunner: CommandRunner

    @State private var newProjectName: String = ""
    @State private var projects: [ProjectItem] = []
    @State private var showSettings: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showOutput: Bool = false
    @State private var isCreating: Bool = false
    @State private var projectToDelete: ProjectItem? = nil

    private let projectService = ProjectService()

    var body: some View {
        VStack(spacing: 0) {
            header
            createRow
            Divider()

            if projects.isEmpty {
                emptyState
            } else {
                projectList
            }

            if showOutput || commandRunner.isRunning {
                Divider()
                CommandOutputView()
                    .frame(height: 200)
            }
        }
        .padding(.top, 8)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .onDisappear { refresh() }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            projectToDelete.map { "Move '\($0.name)' to the Trash?" } ?? "Move to Trash?",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let project = projectToDelete {
                Button("Move to Trash", role: .destructive) {
                    Task { await deleteProject(project) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { refresh() }
        .onChange(of: settings.settings.projectsRoot) { refresh() }
    }

    private var header: some View {
        HStack {
            Text("BMad Manager")
                .font(.headline)
            Spacer()
            Button {
                showOutput.toggle()
            } label: {
                Image(systemName: showOutput ? "terminal.fill" : "terminal")
            }
            .help(showOutput ? "Hide output" : "Show output")
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
                if isCreating {
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
        !isCreating && !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty
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
        List(projects) { project in
            ProjectRowView(
                project: project,
                onClaude: { openInTerminal(project: project, command: settings.settings.claudeCommand) },
                onOpencode: { openInTerminal(project: project, command: settings.settings.opencodeCommand) },
                onDelete: { projectToDelete = project }
            )
        }
    }

    // MARK: - Actions

    private func refresh() {
        projects = projectService.listProjects(in: settings.settings.projectsRoot)
    }

    private func createProject() async {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        // If no module zip is configured yet, prompt for one and remember the
        // choice in Settings so this only happens on the first project.
        if settings.settings.moduleZipPath.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let picked = promptForModuleZip() else {
                errorMessage = "A marketing growth module .zip is required to create a project."
                return
            }
            settings.settings.moduleZipPath = picked.path
        }

        isCreating = true
        showOutput = true
        defer { isCreating = false }

        var moduleTmpDir: URL? = nil

        do {
            let projectURL = try projectService.createProjectFolder(name: name, in: settings.settings.projectsRoot)

            let zip = settings.settings.moduleZipPath.trimmingCharacters(in: .whitespaces)
            let dir = try ZipExtractor.extract(zipPath: zip)
            moduleTmpDir = dir
            let modulePath = dir.path

            let command = settings.settings.initCommand
                .replacingOccurrences(of: "{PROJECT_PATH}", with: projectURL.path)
                .replacingOccurrences(of: "{MODULE_PATH}", with: modulePath)
                .replacingOccurrences(of: "{PROJECT_NAME}", with: name)

            let exitCode = await commandRunner.run(command: command, cwd: projectURL)
            if exitCode != 0 {
                errorMessage = "Init command exited with code \(exitCode). See the output panel for details."
            } else {
                newProjectName = ""
            }
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }

        if let dir = moduleTmpDir {
            ZipExtractor.cleanup(dir)
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

    private func deleteProject(_ project: ProjectItem) async {
        do {
            try await projectService.trash(project)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openInTerminal(project: ProjectItem, command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Command is empty. Set it in Settings."
            return
        }
        do {
            try TerminalLauncher.open(projectPath: project.url.path, command: trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
