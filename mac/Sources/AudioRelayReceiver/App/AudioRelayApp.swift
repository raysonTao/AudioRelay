import SwiftUI

@main
struct AudioRelayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Custom AppDelegate to control window lifecycle behavior.
/// Hides the window to the dock on close rather than terminating the app,
/// so audio playback can continue in the background.
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent automatic termination so the app stays alive
        // when the window is closed.
        NSApp.disableRelaunchOnLogin()
    }

    /// When the user clicks the dock icon while the app is running but the
    /// window is hidden, bring the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Re-show the main window
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }

    /// Hide to dock instead of quitting when the window close button is clicked.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
