import ArgumentParser
import AgentManagerCore
import Foundation

struct WorkflowListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all workflows"
    )

    @Flag(name: .shortAndLong, help: "Show detailed information")
    var verbose = false

    func run() throws {
        let store = WorkflowStore.shared
        let workflows = try store.listWorkflowInfo()

        if workflows.isEmpty {
            print("No workflows configured.")
            print("Create one with: agentctl workflow create <name>")
            return
        }

        if verbose {
            printVerbose(workflows)
        } else {
            printCompact(workflows)
        }
    }

    private func printCompact(_ workflows: [WorkflowInfo]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        print("Workflows:")
        print("")

        for workflow in workflows {
            let status = workflow.statusIndicator
            let lastStatus = workflow.lastRunStatusIcon ?? "○"
            let scheduleIcon = workflow.hasSchedule ? "⏰" : "▶"

            print("  \(status) \(scheduleIcon) \(workflow.name)")
            if let desc = workflow.description {
                print("      \(desc)")
            }
            print("      Jobs: \(workflow.jobCount)  Last: \(lastStatus)", terminator: "")

            if let lastRun = workflow.lastRunDate {
                print(" (\(dateFormatter.string(from: lastRun)))", terminator: "")
            }
            print("")

            if let stats = workflow.stats, stats.totalRuns > 0 {
                print("      Runs: \(stats.totalRuns)  Cost: $\(String(format: "%.4f", stats.totalCost))")
            }
            print("")
        }

        print("Legend: ● enabled  ○ disabled  ⏰ scheduled  ▶ manual  ✓ success  ✗ failed")
    }

    private func printVerbose(_ workflows: [WorkflowInfo]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        for workflow in workflows {
            print("─────────────────────────────────────────")
            print("Name:        \(workflow.name)")
            if let desc = workflow.description {
                print("Description: \(desc)")
            }
            print("Jobs:        \(workflow.jobCount)")
            print("Schedule:    \(workflow.hasSchedule ? "yes" : "no")")
            print("Enabled:     \(workflow.isEnabled ? "yes" : "no")")

            if let lastStatus = workflow.lastRunStatus {
                print("Last Status: \(lastStatus.rawValue)")
            }
            if let lastRun = workflow.lastRunDate {
                print("Last Run:    \(dateFormatter.string(from: lastRun))")
            }

            if let stats = workflow.stats, stats.totalRuns > 0 {
                print("Total Runs:  \(stats.totalRuns)")
                print("Success:     \(stats.successfulRuns) (\(String(format: "%.0f", stats.successRate * 100))%)")
                print("Total Cost:  $\(String(format: "%.4f", stats.totalCost))")
                if let avgDuration = stats.averageDuration {
                    print("Avg Duration:\(String(format: "%.1f", avgDuration))s")
                }
            }
            print("")
        }
    }
}
