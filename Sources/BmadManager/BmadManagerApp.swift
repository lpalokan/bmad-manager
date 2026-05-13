import SwiftUI
import AppKit

@main
struct BmadManagerApp: App {
    // Forces .regular activation when launched as a plain executable (e.g. via
    // `swift run`), which would otherwise default to .prohibited and leave the
    // window invisible. No-op inside the bundled .app, which is already .regular.
    @NSApplicationDelegateAdaptor(BmadManagerAppDelegate.self) private var appDelegate

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

final class BmadManagerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
