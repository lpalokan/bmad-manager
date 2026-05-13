import Foundation

struct AppSettings: Codable, Equatable {
    var projectsRoot: String
    var moduleZipPath: String
    var initCommand: String
    var claudeCommand: String
    var opencodeCommand: String

    static func defaults() -> AppSettings {
        AppSettings(
            projectsRoot: ("~/Projects" as NSString).expandingTildeInPath,
            moduleZipPath: "",
            initCommand: "npx bmad-method install --full --ide claude-code --ide opencode -d '{PROJECT_PATH}' && cp -R '{MODULE_PATH}/'* '{PROJECT_PATH}/'",
            claudeCommand: "claude",
            opencodeCommand: "opencode"
        )
    }
}
