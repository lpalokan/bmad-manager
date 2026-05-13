import Foundation
import SwiftUI

final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { repository.save(settings) }
    }

    private let repository: SettingsRepository

    init(repository: SettingsRepository = FileSettingsRepository()) {
        self.repository = repository
        let loaded = repository.load()
        self.settings = loaded ?? AppSettings.defaults()
        if loaded == nil {
            repository.save(AppSettings.defaults())
        }
    }

    func reset() {
        settings = AppSettings.defaults()
    }
}
