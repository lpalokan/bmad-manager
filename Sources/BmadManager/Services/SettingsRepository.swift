import Foundation

protocol SettingsRepository {
    func load() -> AppSettings?
    func save(_ settings: AppSettings)
}

struct FileSettingsRepository: SettingsRepository {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("bmad-manager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("settings.json")
    }

    func load() -> AppSettings? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    func save(_ settings: AppSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

final class InMemorySettingsRepository: SettingsRepository {
    var stored: AppSettings?

    func load() -> AppSettings? { stored }
    func save(_ settings: AppSettings) { stored = settings }
}
