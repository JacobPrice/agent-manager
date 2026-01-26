import ArgumentParser
import AgentManagerCore
import Foundation

struct EditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Open agent YAML in editor"
    )

    @Argument(help: "Name of the agent to edit")
    var name: String

    func run() throws {
        let store = AgentStore.shared

        // Check if agent exists
        guard store.exists(name: name) else {
            throw ValidationError("Agent '\(name)' not found. Create it with: agentctl create \(name)")
        }

        let agentPath = store.agentPath(name: name)

        let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vim"
        print("Opening \(agentPath.path) in \(editor)...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, agentPath.path]

        // Connect to terminal for interactive editing
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        // Validate the edited YAML
        do {
            _ = try store.load(name: name)
            print("Agent '\(name)' updated successfully.")
        } catch {
            print("Warning: Agent YAML may be invalid: \(error.localizedDescription)")
            print("Run 'agentctl show \(name)' to check for errors.")
        }
    }
}
