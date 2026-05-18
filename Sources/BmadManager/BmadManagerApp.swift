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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Quit BMad Manager") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

final class BmadManagerAppDelegate: NSObject, NSApplicationDelegate {
    /// Set activation policy *before* the menu bar is wired so Cmd-Q and
    /// other system shortcuts work from the first press.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
