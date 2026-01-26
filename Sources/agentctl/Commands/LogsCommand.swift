import ArgumentParser
import AgentManagerCore
import Foundation
import Darwin

struct LogsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "View agent run logs"
    )

    @Argument(help: "Name of the agent")
    var name: String

    @Flag(name: .shortAndLong, help: "Follow the log output (like tail -f)")
    var follow = false

    @Option(name: .shortAndLong, help: "Number of lines to show (default: all)")
    var lines: Int?

    @Flag(name: .long, help: "List all log files instead of showing content")
    var list = false

    @Option(name: .long, help: "Show specific log file by index (1 = most recent)")
    var index: Int?

    func run() throws {
        let store = AgentStore.shared
        let logManager = LogManager.shared

        // Verify agent exists
        guard store.exists(name: name) else {
            throw ValidationError("Agent '\(name)' not found.")
        }

        // List mode
        if list {
            try listLogs(logManager: logManager)
            return
        }

        // Get the log to show
        let logs = try logManager.listLogs(agentName: name)

        guard !logs.isEmpty else {
            print("No logs found for agent '\(name)'.")
            print("Run the agent with: agentctl run \(name)")
            return
        }

        let logIndex = (index ?? 1) - 1
        guard logIndex >= 0 && logIndex < logs.count else {
            throw ValidationError("Log index \(index ?? 1) out of range. Use --list to see available logs.")
        }

        let logEntry = logs[logIndex]

        if follow {
            try followLog(logEntry: logEntry, logManager: logManager)
        } else {
            try showLog(logEntry: logEntry, logManager: logManager)
        }
    }

    private func listLogs(logManager: LogManager) throws {
        let logs = try logManager.listLogs(agentName: name)

        if logs.isEmpty {
            print("No logs found for agent '\(name)'.")
            return
        }

        print("Logs for '\(name)':")
        print("")

        for (i, log) in logs.enumerated() {
            let marker = i == 0 ? " (latest)" : ""
            print("  \(i + 1). \(log.formattedDate) (\(log.formattedSize))\(marker)")
        }

        print("")
        print("View a log: agentctl logs \(name) --index N")
        print("View latest: agentctl logs \(name)")
    }

    private func showLog(logEntry: LogEntry, logManager: LogManager) throws {
        print("Log: \(logEntry.filename)")
        print("Date: \(logEntry.formattedDate)")
        print("Size: \(logEntry.formattedSize)")
        print("─────────────────────────────────────────────────────────────────────")
        print("")

        if let n = lines {
            let content = try logManager.tailLog(at: logEntry.url, lines: n)
            print(content)
        } else {
            let content = try logManager.readLog(at: logEntry.url)
            print(content)
        }
    }

    private func followLog(logEntry: LogEntry, logManager: LogManager) throws {
        print("Following log: \(logEntry.filename)")
        print("Press Ctrl+C to stop")
        print("─────────────────────────────────────────────────────────────────────")
        print("")

        // Set up signal handling for clean exit
        signal(SIGINT) { _ in
            print("\nStopped.")
            Darwin.exit(0)
        }

        let follower = try logManager.followLog(at: logEntry.url)

        // Use a semaphore to keep the program running
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            for await line in follower.lines() {
                print(line)
            }
            semaphore.signal()
        }

        semaphore.wait()
    }
}
