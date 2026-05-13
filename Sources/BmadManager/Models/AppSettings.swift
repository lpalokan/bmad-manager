import Foundation

struct AppSettings: Codable, Equatable {
    var projectsRoot: String
    var moduleZipPath: String
    var initCommand: String
    var claudeCommand: String
    var opencodeCommand: String

    static func defaults() -> AppSettings {
        // Headless BMad install per docs.bmad-method.org/how-to/install-bmad
        // (--yes for non-interactive, --modules for the always-on set,
        // --tools for IDE configuration, --directory for the target).
        // Always installs the BMad Method core (bmm), BMad Builder (bmb),
        // and Creative Intelligence Suite (cis), and registers the unzipped
        // marketing growth bundle via `--custom-source` so its modules show
        // up as proper BMad modules (not just files dropped on the project).
        //
        // If you upgrade an existing install, hit "Reset to defaults" in
        // Settings so the persisted command picks up these flags.
        AppSettings(
            projectsRoot: ("~/Projects" as NSString).expandingTildeInPath,
            moduleZipPath: "",
            initCommand: "npx bmad-method install --yes --modules bmm,bmb,cis --tools claude-code,opencode --custom-source '{MODULE_PATH}' --directory '{PROJECT_PATH}'",
            claudeCommand: "claude",
            opencodeCommand: "opencode"
        )
    }
}
