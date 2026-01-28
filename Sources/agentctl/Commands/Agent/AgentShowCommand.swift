import ArgumentParser
import AgentManagerCore
import Foundation

struct AgentShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show agent template YAML"
    )

    @Argument(help: "Name of the agent to show")
    var name: String

    func run() throws {
        let store = AgentStore.shared

        // Load agent
        let agent = try store.load(name: name)

        // Print YAML
        let yaml = try agent.toYAML()
        print(yaml)
    }
}
