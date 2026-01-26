import ArgumentParser
import AgentManagerCore
import Foundation

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Execute an agent manually"
    )

    @Argument(help: "Name of the agent to run")
    var name: String

    @Flag(name: .long, help: "Show what would be executed without running")
    var dryRun = false

    func run() throws {
        let store = AgentStore.shared
        let runner = AgentRunner.shared

        // Load agent
        let agent = try store.load(name: name)

        print("Running agent: \(agent.name)")
        if dryRun {
            print("(dry run mode)")
        }
        print("")

        // Execute
        let result = try runner.run(agent: agent, dryRun: dryRun)

        // Summary
        print("")
        if result.success {
            print("Agent completed successfully.")
            print("Duration: \(String(format: "%.1f", result.duration))s")
            print("Log file: \(result.logFile.path)")
        } else {
            print("Agent execution failed.")
            throw ExitCode.failure
        }
    }
}
