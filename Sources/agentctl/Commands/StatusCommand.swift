import ArgumentParser
import AgentManagerCore
import Foundation

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show recent workflow runs"
    )

    @Argument(help: "Name of the workflow")
    var name: String

    @Option(name: .shortAndLong, help: "Number of recent runs to show")
    var limit: Int = 5

    @Option(name: .long, help: "Show details for a specific run ID")
    var runId: String?

    func run() throws {
        let store = WorkflowStore.shared
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium

        // Check workflow exists
        guard store.exists(name: name) else {
            throw ValidationError("Workflow '\(name)' not found.")
        }

        // Show specific run or list recent runs
        if let id = runId {
            let run = try store.loadRun(workflowName: name, runId: id)
            printRunDetails(run, dateFormatter: dateFormatter)
        } else {
            let runs = try store.listRuns(workflowName: name, limit: limit)

            if runs.isEmpty {
                print("No runs found for workflow '\(name)'.")
                print("Run with: agentctl run \(name)")
                return
            }

            print("Recent runs for '\(name)':")
            print("")

            for run in runs {
                let statusIcon = statusIcon(for: run.status)
                let date = dateFormatter.string(from: run.startTime)
                let duration = run.duration.map { String(format: "%.1fs", $0) } ?? "running"

                print("  \(statusIcon) \(run.id.prefix(8))  \(date)  \(duration)  $\(String(format: "%.4f", run.totalCost))")

                // Show job summary
                let completed = run.completedJobCount
                let failed = run.failedJobCount
                let total = run.jobResults.count
                print("      Jobs: \(completed)/\(total) completed", terminator: "")
                if failed > 0 {
                    print(", \(failed) failed", terminator: "")
                }
                print("")
            }

            print("")
            print("Show details: agentctl status \(name) --run-id <id>")
        }
    }

    private func printRunDetails(_ run: WorkflowRun, dateFormatter: DateFormatter) {
        print("Workflow Run: \(run.id)")
        print("Workflow:     \(run.workflowName)")
        print("Status:       \(run.status.rawValue)")
        print("Started:      \(dateFormatter.string(from: run.startTime))")

        if let endTime = run.endTime {
            print("Ended:        \(dateFormatter.string(from: endTime))")
        }

        if let duration = run.duration {
            print("Duration:     \(String(format: "%.1f", duration))s")
        }

        if run.isDryRun {
            print("Mode:         dry run")
        }

        print("")
        print("Jobs:")

        for (jobName, result) in run.jobResults.sorted(by: { $0.key < $1.key }) {
            let icon = jobStatusIcon(for: result.status)
            print("  \(icon) \(jobName): \(result.status.rawValue)")

            if let duration = result.duration {
                print("      Duration: \(String(format: "%.1f", duration))s")
            }

            if let cost = result.cost {
                print("      Cost: $\(String(format: "%.4f", cost))")
            }

            if let tokens = result.totalTokens {
                print("      Tokens: \(tokens)")
            }

            if !result.outputs.isEmpty {
                print("      Outputs:")
                for (key, value) in result.outputs.sorted(by: { $0.key < $1.key }) {
                    let truncated = value.count > 50 ? String(value.prefix(50)) + "..." : value
                    print("        \(key): \(truncated)")
                }
            }

            if let error = result.errorMessage {
                print("      Error: \(error)")
            }

            print("")
        }

        print("Total Cost:   $\(String(format: "%.4f", run.totalCost))")
        print("Total Tokens: \(run.totalTokens)")
    }

    private func statusIcon(for status: WorkflowStatus) -> String {
        switch status {
        case .pending: return "○"
        case .running: return "◐"
        case .completed: return "●"
        case .failed: return "✗"
        case .cancelled: return "◌"
        }
    }

    private func jobStatusIcon(for status: JobStatus) -> String {
        switch status {
        case .pending: return "○"
        case .running: return "◐"
        case .completed: return "●"
        case .failed: return "✗"
        case .skipped: return "⊘"
        case .cancelled: return "◌"
        }
    }
}
