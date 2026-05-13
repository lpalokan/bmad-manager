import SwiftUI

@main
struct BmadManagerApp: App {
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var commandRunner = CommandRunner()

    var body: some Scene {
        WindowGroup("BMad Manager") {
            ContentView()
                .environmentObject(settingsStore)
                .environmentObject(commandRunner)
                .frame(minWidth: 640, minHeight: 480)
        }
    }
}
