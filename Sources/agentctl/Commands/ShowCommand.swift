import ArgumentParser
import AgentManagerCore
import Foundation

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Display agent configuration"
    )

    @Argument(help: "Name of the agent to show")
    var name: String

    @Flag(name: .shortAndLong, help: "Show raw YAML")
    var raw = false

    func run() throws {
        let store = AgentStore.shared
        let agent = try store.load(name: name)

        if raw {
            let yaml = try agent.toYAML()
            print(yaml)
        } else {
            printFormatted(agent)
        }
    }

    private func printFormatted(_ agent: Agent) {
        let launchStatus = LaunchAgentManager.shared.status(agentName: agent.name)

        print("Agent: \(agent.name)")
        print("═══════════════════════════════════════════")
        print("")
        print("Description:       \(agent.description)")
        print("Working Directory: \(agent.workingDirectory)")
        print("")

        // Trigger
        print("Trigger:")
        print("  Type: \(agent.trigger.type.rawValue)")
        if let hour = agent.trigger.hour, let minute = agent.trigger.minute {
            print("  Time: \(String(format: "%02d:%02d", hour, minute))")
        }
        print("")

        // Schedule status
        print("Schedule Status: \(launchStatus.description)")
        print("")

        // Allowed tools
        print("Allowed Tools:")
        for tool in agent.allowedTools {
            print("  - \(tool)")
        }
        print("")

        // Limits
        print("Limits:")
        print("  Max Turns:  \(agent.maxTurns)")
        print("  Max Budget: $\(String(format: "%.2f", agent.maxBudgetUSD))")
        print("")

        // Context script
        if let contextScript = agent.contextScript {
            print("Context Script:")
            print("───────────────────────────────────────────")
            for line in contextScript.components(separatedBy: .newlines) {
                print("  \(line)")
            }
            print("───────────────────────────────────────────")
            print("")
        }

        // Prompt
        print("Prompt:")
        print("───────────────────────────────────────────")
        for line in agent.prompt.components(separatedBy: .newlines) {
            print("  \(line)")
        }
        print("───────────────────────────────────────────")
    }
}
