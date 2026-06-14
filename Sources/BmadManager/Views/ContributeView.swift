import SwiftUI
import AppKit

/// Sheet for proposing additions (personal skills + project contexts) to the
/// shared repo as a pull request. Nothing is changed in the repo directly — a
/// reviewer merges the additions.
struct ContributeView: View {
    let settings: AppSettings
    /// Project-sourced contexts the user could contribute (GitHub-sourced ones
    /// are already in the repo, so they're filtered out by the caller).
    let projectContexts: [CompanyContext]
    let onClose: () -> Void

    /// Contributor token first, falling back to the read-only sync token (which
    /// will surface a clear permission error rather than failing silently).
    private let contributorStore: any TokenStore =
        KeychainTokenStore(account: "skills-repo-contributor-token")
    private let syncStore: any TokenStore = KeychainTokenStore()

    @State private var skills: [ContributableSkill] = []
    @State private var selectedSkills: Set<URL> = []
    @State private var selectedContexts: Set<URL> = []
    @State private var contextNames: [URL: String] = [:]
    @State private var title: String = ""
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var prURL: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contribute to the shared repo")
                .font(.headline)
            Text("Propose your own skills and project contexts as a pull request. A reviewer merges your additions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let prURL {
                Text("Pull request opened.")
                    .foregroundStyle(.green)
                Link(prURL, destination: URL(string: prURL) ?? URL(fileURLWithPath: "/"))
            } else {
                content
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(prURL == nil ? "Cancel" : "Close") { onClose() }
                if prURL == nil {
                    Button {
                        Task { await submit() }
                    } label: {
                        if submitting { ProgressView().controlSize(.small) } else { Text("Open pull request") }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { skills = ContributionService.enumeratePersonalSkills() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Personal skills").font(.subheadline.bold())
                if skills.isEmpty {
                    Text("No personal skills found in your skills folders.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(skills) { skill in
                        Toggle(isOn: binding(for: skill.directory, in: $selectedSkills)) {
                            Text("\(skill.name)  ").font(.callout)
                                + Text("(\(skill.tool))").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Project contexts").font(.subheadline.bold())
                if projectContexts.isEmpty {
                    Text("No project contexts found.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(projectContexts) { context in
                        HStack {
                            Toggle(isOn: binding(for: context.directoryURL, in: $selectedContexts)) {
                                Text(context.displayName).font(.callout)
                            }
                            if selectedContexts.contains(context.directoryURL) {
                                TextField("Folder name", text: nameBinding(for: context))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Pull request title (optional)").font(.caption).foregroundStyle(.secondary)
                TextField("Add skill / context", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var canSubmit: Bool {
        !submitting && (!selectedSkills.isEmpty || !selectedContexts.isEmpty)
    }

    private func binding(for key: URL, in set: Binding<Set<URL>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(key) },
            set: { isOn in
                if isOn { set.wrappedValue.insert(key) } else { set.wrappedValue.remove(key) }
            }
        )
    }

    private func nameBinding(for context: CompanyContext) -> Binding<String> {
        Binding(
            get: { contextNames[context.directoryURL] ?? context.projectName },
            set: { contextNames[context.directoryURL] = $0 }
        )
    }

    private func submit() async {
        guard canSubmit else { return }
        submitting = true
        errorMessage = nil
        defer { submitting = false }

        guard let (owner, repo) = ContributionService.parseOwnerRepo(settings.skillsRepoURL) else {
            errorMessage = settings.skillsRepoURL.trimmingCharacters(in: .whitespaces).isEmpty
                ? ContributionError.noRepoURL.localizedDescription
                : ContributionError.badRepoURL(settings.skillsRepoURL).localizedDescription
            return
        }
        guard let token = contributorStore.loadToken() ?? syncStore.loadToken() else {
            errorMessage = ContributionError.noToken.localizedDescription
            return
        }

        let skillSelections = skills
            .filter { selectedSkills.contains($0.directory) }
            .map { ContributionService.SkillSelection(name: $0.name, directory: $0.directory) }
        let contextSelections = projectContexts
            .filter { selectedContexts.contains($0.directoryURL) }
            .map { context in
                ContributionService.ContextSelection(
                    targetName: contextNames[context.directoryURL] ?? context.projectName,
                    directory: context.directoryURL,
                    files: context.files
                )
            }

        let client = URLSessionGitHubClient(token: token)
        let timestamp = String(Int(Date().timeIntervalSince1970))
        do {
            let result = try await ContributionService.submitContribution(
                client: client, owner: owner, repo: repo,
                skills: skillSelections, contexts: contextSelections,
                title: title, timestamp: timestamp
            )
            prURL = result.url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
