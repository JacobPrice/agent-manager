import ArgumentParser
import AgentManagerCore
import Foundation

struct EnableCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Install LaunchAgent to activate scheduled runs"
    )

    @Argument(help: "Name of the agent to enable")
    var name: String

    func run() throws {
        let store = AgentStore.shared
        let launchAgent = LaunchAgentManager.shared

        // Load agent
        let agent = try store.load(name: name)

        // Verify it's a scheduled agent
        guard agent.trigger.type == .schedule else {
            throw ValidationError(
                "Agent '\(name)' has trigger type '\(agent.trigger.type.rawValue)'. " +
                "Only scheduled agents can be enabled."
            )
        }

        guard let hour = agent.trigger.hour, let minute = agent.trigger.minute else {
            throw ValidationError(
                "Agent '\(name)' is missing schedule time (hour/minute)."
            )
        }

        // Check if already enabled
        if launchAgent.isInstalled(agentName: name) {
            print("Agent '\(name)' is already enabled. Reinstalling...")
            try launchAgent.uninstall(agentName: name)
        }

        // Install LaunchAgent
        print("Installing LaunchAgent for '\(name)'...")
        try launchAgent.install(agent: agent)

        print("")
        print("Agent '\(name)' enabled!")
        print("Scheduled to run daily at \(String(format: "%02d:%02d", hour, minute))")
        print("")
        print("Plist installed at: \(launchAgent.plistPath(agentName: name).path)")
        print("")
        print("Verify with: launchctl list | grep agentmanager.\(name)")
        print("Run now with: agentctl run \(name)")
    }
}
