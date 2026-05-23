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
    @State private var showSettings: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            createRow
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
                .onDisappear { coordinator.refresh() }
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
                    Task { await coordinator.deleteProject(project) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { coordinator.refresh() }
        .onChange(of: settings.settings.projectsRoot) { coordinator.refresh() }
        .onChange(of: settings.settings.projectSortOrder) { coordinator.refresh() }
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
                    coordinator.openInTerminal(
                        project: project,
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
                onOpenFolder: { coordinator.openProjectFolder(project) },
                onDelete: { coordinator.projectToDelete = project }
            )
        }
    }

    // MARK: - Actions

    private func createProject() async {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        await coordinator.createProject(name: name) { [self] in
            promptForModuleZip()
        }

        if coordinator.errorMessage == nil {
            newProjectName = ""
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
