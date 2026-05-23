import SwiftUI
import AppKit

@main
struct BmadManagerApp: App {
    // Forces .regular activation when launched as a plain executable (e.g. via
    // `swift run`), which would otherwise default to .prohibited and leave the
    // window invisible. No-op inside the bundled .app, which is already .regular.
    @NSApplicationDelegateAdaptor(BmadManagerAppDelegate.self) private var appDelegate

    // No init-time capture of these stores. Both flow into the
    // coordinator's methods per-call from `ContentView`, which reads
    // them off its own `@EnvironmentObject` bindings. Capturing them
    // here used to hand the coordinator a different SettingsStore /
    // CommandRunner instance than the one SwiftUI ended up installing
    // on the view tree — that drift was the root cause of the
    // Terminal-vs-iTerm2, projects-root-doesn't-reindex, and
    // empty-output-panel bugs.
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var commandRunner = CommandRunner()
    @StateObject private var projectCoordinator = ProjectCoordinator()

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
