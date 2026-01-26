import ArgumentParser
import AgentManagerCore
import Foundation

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all agents with status"
    )

    @Flag(name: .shortAndLong, help: "Show detailed information")
    var verbose = false

    func run() throws {
        let store = AgentStore.shared
        let agents = try store.listAgentInfo()

        if agents.isEmpty {
            print("No agents configured.")
            print("Create one with: agentctl create <name>")
            return
        }

        if verbose {
            printVerbose(agents)
        } else {
            printCompact(agents)
        }
    }

    private func printCompact(_ agents: [AgentInfo]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        print("Agents:")
        print("")

        for agent in agents {
            let status = agent.statusIndicator
            let trigger = agent.triggerIcon
            let lastRun = agent.lastRun.map { dateFormatter.string(from: $0) } ?? "never"

            print("  \(status) \(trigger) \(agent.name)")
            print("      \(agent.description)")
            print("      Last run: \(lastRun)")
            print("")
        }

        print("Legend: ● enabled  ○ disabled  ⏰ scheduled  ▶ manual  👁 file-watch")
    }

    private func printVerbose(_ agents: [AgentInfo]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        for agent in agents {
            print("─────────────────────────────────────────")
            print("Name:        \(agent.name)")
            print("Description: \(agent.description)")
            print("Trigger:     \(agent.triggerType.rawValue)")
            print("Enabled:     \(agent.isEnabled ? "yes" : "no")")
            if let lastRun = agent.lastRun {
                print("Last Run:    \(dateFormatter.string(from: lastRun))")
            } else {
                print("Last Run:    never")
            }
            print("")
        }
    }
}
