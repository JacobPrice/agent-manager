import ArgumentParser
import AgentManagerCore
import Foundation

struct AgentCreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new agent template"
    )

    @Argument(help: "Name for the new agent")
    var name: String

    @Option(name: .shortAndLong, help: "Agent description")
    var description: String?

    @Option(name: .shortAndLong, help: "Working directory")
    var workingDirectory: String?

    @Flag(name: .long, help: "Open in editor after creating")
    var edit = false

    @Flag(name: .shortAndLong, help: "Create from template without prompting")
    var template = false

    func run() throws {
        let store = AgentStore.shared

        // Validate name
        guard isValidName(name) else {
            throw ValidationError("Invalid agent name: '\(name)'. Use only letters, numbers, and hyphens.")
        }

        // Check if agent already exists
        guard !store.exists(name: name) else {
            throw ValidationError("Agent '\(name)' already exists. Use 'agentctl agent edit \(name)' to modify it.")
        }

        // Create template agent
        var agent = Agent.template(name: name)

        // Apply any provided options
        if let desc = description {
            agent = Agent(
                name: agent.name,
                description: desc,
                trigger: agent.trigger,
                workingDirectory: agent.workingDirectory,
                contextScript: agent.contextScript,
                prompt: agent.prompt,
                allowedTools: agent.allowedTools,
                maxTurns: agent.maxTurns,
                maxBudgetUSD: agent.maxBudgetUSD
            )
        }

        if let wd = workingDirectory {
            agent = Agent(
                name: agent.name,
                description: agent.description,
                trigger: agent.trigger,
                workingDirectory: wd,
                contextScript: agent.contextScript,
                prompt: agent.prompt,
                allowedTools: agent.allowedTools,
                maxTurns: agent.maxTurns,
                maxBudgetUSD: agent.maxBudgetUSD
            )
        }

        // Save the agent
        try store.save(agent)

        let agentPath = store.agentPath(name: name)
        print("Created agent '\(name)' at: \(agentPath.path)")

        if edit || !template {
            print("Opening in editor...")
            try openInEditor(path: agentPath.path)
        } else {
            print("Edit with: agentctl agent edit \(name)")
        }
    }

    private func isValidName(_ name: String) -> Bool {
        let pattern = "^[a-zA-Z][a-zA-Z0-9-]*$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    private func openInEditor(path: String) throws {
        let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vim"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, path]

        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()
    }
}
