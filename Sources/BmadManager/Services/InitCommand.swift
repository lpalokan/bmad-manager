import Foundation

/// Build-time shaping of the configured init-command template, applied where
/// the command is assembled rather than stored in settings.
enum InitCommand {
    /// The output folder new projects are installed with. `bmad-method`'s own
    /// default is `_bmad-output`, which leaves a project that also uses
    /// marketing-growth with two output folders — the deliverables under
    /// `output/` and core's artifacts under `_bmad-output/`. Installing with
    /// this value puts core, bmm/bmb/cis and marketing-growth in one place.
    static let createOutputFolder = "output"

    /// Appends `--output-folder output` to an init-command template.
    ///
    /// **Create path only.** The installer lets a CLI flag override a project's
    /// remembered answer (`tools/installer/ui.js` spreads the CLI-collected
    /// core config over the project's loaded config), so passing this on the
    /// update path would silently flip an existing project's
    /// `[core] output_folder` from `_bmad-output` to `output` while its files
    /// stayed put. `ProjectUpdater` therefore substitutes the configured
    /// command directly and never calls this.
    ///
    /// A template that already chooses an output folder — via `--output-folder`
    /// or `--set core.output_folder=` — is returned unchanged: a deliberate
    /// user choice in `settings.json` wins. The stored setting is never
    /// rewritten; the flag exists only in the command handed to the shell for
    /// this one install.
    static func withCreateOutputFolder(_ template: String) -> String {
        guard !template.contains("--output-folder"),
              !template.contains("--set core.output_folder=")
        else { return template }
        return "\(template) --output-folder \(createOutputFolder)"
    }
}
