import SwiftUI
import AgentManagerCore

@main
struct AgentManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Agent") {
                    NotificationCenter.default.post(name: .createNewAgent, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("Refresh Agents") {
                    NotificationCenter.default.post(name: .refreshAgents, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let createNewAgent = Notification.Name("createNewAgent")
    static let refreshAgents = Notification.Name("refreshAgents")
}
