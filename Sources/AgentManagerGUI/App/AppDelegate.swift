import Cocoa
import AgentManagerCore

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure agent-manager directories exist
        do {
            try AgentStore.shared.ensureDirectoriesExist()
        } catch {
            print("Warning: Could not create agent-manager directories: \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
