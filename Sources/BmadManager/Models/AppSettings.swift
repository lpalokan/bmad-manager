import Foundation

struct AppSettings: Codable, Equatable {
    var projectsRoot: String
    var moduleZipPath: String
    var initCommand: String
    var claudeCommand: String
    var opencodeCommand: String

    static func defaults() -> AppSettings {
        // Headless BMad install. The `--full` flag (which bmad-method's npm
        // package accepts even though the public docs list `--yes --modules
        // <list>` instead) installs the BMad Method core, Builder, and
        // Creative Intelligence Suite with their defaults in one shot — the
        // documented `--yes --modules bmm,bmb,cis` form stalls at the CIS
        // configuration step in practice. The trailing cp lays the unzipped
        // marketing growth module on top of the project.
        AppSettings(
            projectsRoot: ("~/Projects" as NSString).expandingTildeInPath,
            moduleZipPath: "",
            initCommand: "npx bmad-method install --full --ide claude-code --ide opencode -d '{PROJECT_PATH}' && cp -R '{MODULE_PATH}/.' '{PROJECT_PATH}/'",
            claudeCommand: "claude",
            opencodeCommand: "opencode"
        )
    }
}
