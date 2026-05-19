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
    @StateObject private var projectCoordinator: ProjectCoordinator = {
        // Cannot capture other @StateObject properties in the default-value
        // closure because they may not exist yet.  We substitute the real
        // runner in init() after all StateObjects are created.
        ProjectCoordinator(settings: SettingsStore(), runCommand: { _, _ in 0 })
    }()

    init() {
        // Wire the real CommandRunner after @StateObject wrappers are
        // allocated so we don't race on instance creation order.
        let store = settingsStore
        let runner = commandRunner
        _projectCoordinator = StateObject(wrappedValue: ProjectCoordinator(
            settings: store,
            runCommand: { cmd, cwd in await runner.run(command: cmd, cwd: cwd) }
        ))
    }

    var body: some Scene {
        WindowGroup("BMad Manager") {
            ContentView()
                .environmentObject(settingsStore)
                .environmentObject(commandRunner)
                .environmentObject(projectCoordinator)
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
