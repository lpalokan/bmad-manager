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
        // and Creative Intelligence Suite (cis). The trailing cp lays the
        // unzipped marketing growth module on top of the project.
        //
        // Note: the older `--full` flag was removed from bmad-method's npm
        // package. If you upgrade an existing install, hit "Reset to defaults"
        // in Settings so the persisted command picks up these flags.
        AppSettings(
            projectsRoot: ("~/Projects" as NSString).expandingTildeInPath,
            moduleZipPath: "",
            initCommand: "npx bmad-method install --yes --modules bmm,bmb,cis --tools claude-code,opencode --directory '{PROJECT_PATH}' && cp -R '{MODULE_PATH}/.' '{PROJECT_PATH}/'",
            claudeCommand: "claude",
            opencodeCommand: "opencode"
        )
    }
}
