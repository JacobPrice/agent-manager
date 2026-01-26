import ArgumentParser
import AgentManagerCore
import Foundation

struct DisableCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Remove LaunchAgent to deactivate scheduled runs"
    )

    @Argument(help: "Name of the agent to disable")
    var name: String

    func run() throws {
        let store = AgentStore.shared
        let launchAgent = LaunchAgentManager.shared

        // Verify agent exists
        guard store.exists(name: name) else {
            throw ValidationError("Agent '\(name)' not found.")
        }

        // Check if enabled
        guard launchAgent.isInstalled(agentName: name) else {
            print("Agent '\(name)' is not enabled.")
            return
        }

        // Uninstall
        print("Disabling agent '\(name)'...")
        try launchAgent.uninstall(agentName: name)

        print("Agent '\(name)' disabled.")
        print("Scheduled runs have been stopped.")
        print("")
        print("The agent configuration is still saved.")
        print("Re-enable with: agentctl enable \(name)")
        print("Run manually with: agentctl run \(name)")
    }
}
