import ArgumentParser
import AgentManagerCore
import Foundation

struct AgentListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all agent templates"
    )

    @Flag(name: .shortAndLong, help: "Show detailed information")
    var verbose = false

    func run() throws {
        let store = AgentStore.shared
        let agents = try store.listAgentInfo()

        if agents.isEmpty {
            print("No agent templates configured.")
            print("Create one with: agentctl agent create <name>")
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

        print("Agent Templates:")
        print("")

        for agent in agents {
            let status = agent.statusIndicator
            let trigger = agent.triggerIcon

            print("  \(status) \(trigger) \(agent.name)")
            print("      \(agent.description)")

            if let stats = agent.stats {
                print("      Runs: \(stats.runCount)  Cost: $\(String(format: "%.4f", stats.totalCost))")
            }
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

            if let stats = agent.stats {
                print("Run Count:   \(stats.runCount)")
                print("Total Cost:  $\(String(format: "%.4f", stats.totalCost))")
                if let avgCost = stats.averageCost {
                    print("Avg Cost:    $\(String(format: "%.4f", avgCost))")
                }
            }
            print("")
        }
    }
}
