import ArgumentParser
import AgentManagerCore
import Foundation

struct WorkflowLogsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "View workflow run logs"
    )

    @Argument(help: "Name of the workflow")
    var name: String

    @Option(name: .long, help: "Show logs for a specific run ID")
    var runId: String?

    @Option(name: .long, help: "Show logs for a specific job")
    var job: String?

    @Flag(name: .shortAndLong, help: "Follow log output (tail -f style)")
    var follow = false

    @Option(name: .shortAndLong, help: "Number of lines to show")
    var lines: Int = 50

    func run() throws {
        let store = WorkflowStore.shared

        // Check workflow exists
        guard store.exists(name: name) else {
            throw ValidationError("Workflow '\(name)' not found.")
        }

        // Get run ID (use most recent if not specified)
        let targetRunId: String
        if let id = runId {
            targetRunId = id
        } else {
            guard let lastRun = try store.loadLastRun(workflowName: name) else {
                print("No runs found for workflow '\(name)'.")
                return
            }
            targetRunId = lastRun.id
            print("Showing logs for most recent run: \(targetRunId.prefix(8))")
            print("")
        }

        // Load the run
        let workflowRun = try store.loadRun(workflowName: name, runId: targetRunId)

        // If job is specified, show that job's log
        if let jobName = job {
            guard let jobResult = workflowRun.jobResults[jobName] else {
                throw ValidationError("Job '\(jobName)' not found in run.")
            }

            guard let logFile = jobResult.logFile else {
                print("No log file found for job '\(jobName)'.")
                return
            }

            try showLogFile(logFile, lines: lines, follow: follow)
        } else {
            // Show summary of all job logs
            print("Run ID: \(workflowRun.id)")
            print("Status: \(workflowRun.status.rawValue)")
            print("")

            for (jobName, result) in workflowRun.jobResults.sorted(by: { $0.key < $1.key }) {
                print("─── \(jobName) (\(result.status.rawValue)) ───")

                if let output = result.claudeOutput {
                    // Show truncated output
                    let outputLines = output.components(separatedBy: .newlines)
                    let displayLines = outputLines.prefix(10)
                    for line in displayLines {
                        print(line)
                    }
                    if outputLines.count > 10 {
                        print("... (\(outputLines.count - 10) more lines)")
                    }
                } else if let error = result.errorMessage {
                    print("Error: \(error)")
                } else if result.status == .skipped {
                    print("(skipped)")
                } else {
                    print("(no output)")
                }
                print("")
            }

            print("─────────────────────────────────")
            print("View specific job: agentctl logs \(name) --job <jobName>")
        }
    }

    private func showLogFile(_ url: URL, lines: Int, follow: Bool) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Log file not found: \(url.path)")
            return
        }

        if follow {
            // Use tail -f
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
            process.arguments = ["-f", "-n", String(lines), url.path]
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError

            try process.run()
            process.waitUntilExit()
        } else {
            // Read and display last N lines
            let content = try String(contentsOf: url, encoding: .utf8)
            let allLines = content.components(separatedBy: .newlines)
            let displayLines = allLines.suffix(lines)

            for line in displayLines {
                print(line)
            }
        }
    }
}
