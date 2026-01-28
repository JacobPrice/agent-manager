import SwiftUI
import AgentManagerCore

struct WorkflowDetailView: View {
    let workflowName: String
    let onRun: (Workflow) -> Void
    let onSaved: () -> Void

    @State private var workflow: Workflow?
    @State private var workflowInfo: WorkflowInfo?
    @State private var showingYAMLEditor = false
    @State private var showingRunHistory = false
    @State private var errorMessage: String?

    private let store = WorkflowStore.shared
    private let launchAgent = WorkflowLaunchAgentManager.shared

    var body: some View {
        Group {
            if let workflow = workflow {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        headerSection(workflow)

                        Divider()

                        // Jobs DAG
                        jobsSection(workflow)

                        Divider()

                        // Stats
                        if let info = workflowInfo, let stats = info.stats, stats.totalRuns > 0 {
                            statsSection(stats)
                            Divider()
                        }

                        // Recent runs
                        recentRunsSection

                        Spacer()
                    }
                    .padding()
                }
            } else if let error = errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(workflowName)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let workflow = workflow {
                        onRun(workflow)
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(workflow == nil)

                Button {
                    showingYAMLEditor = true
                } label: {
                    Label("Edit YAML", systemImage: "doc.text")
                }

                if let workflow = workflow, workflow.on.hasSchedule {
                    Button {
                        toggleEnabled()
                    } label: {
                        if workflowInfo?.isEnabled == true {
                            Label("Disable", systemImage: "stop.circle")
                        } else {
                            Label("Enable", systemImage: "play.circle")
                        }
                    }
                }
            }
        }
        .onAppear {
            loadWorkflow()
        }
        .sheet(isPresented: $showingYAMLEditor) {
            WorkflowYAMLEditorView(workflowName: workflowName, onSave: {
                loadWorkflow()
                onSaved()
            })
            .frame(minWidth: 600, minHeight: 500)
        }
    }

    @ViewBuilder
    private func headerSection(_ workflow: Workflow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workflow.name)
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                if let info = workflowInfo {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(info.isEnabled ? Color.green : Color.secondary.opacity(0.3))
                            .frame(width: 10, height: 10)
                        Text(info.isEnabled ? "Enabled" : "Disabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let description = workflow.description {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Label("\(workflow.jobs.count) jobs", systemImage: "list.bullet")
                    .font(.caption)

                if workflow.on.hasSchedule {
                    Label("Scheduled", systemImage: "clock")
                        .font(.caption)
                } else {
                    Label("Manual", systemImage: "hand.tap")
                        .font(.caption)
                }

                if let maxCost = workflow.maxCostUSD {
                    Label("$\(String(format: "%.2f", maxCost)) max", systemImage: "dollarsign.circle")
                        .font(.caption)
                }
            }
            .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func jobsSection(_ workflow: Workflow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jobs")
                .font(.headline)

            WorkflowDAGView(workflow: workflow)
                .frame(minHeight: 200)
        }
    }

    @ViewBuilder
    private func statsSection(_ stats: WorkflowStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statistics")
                .font(.headline)

            HStack(spacing: 24) {
                StatBox(title: "Total Runs", value: "\(stats.totalRuns)")
                StatBox(title: "Success Rate", value: "\(String(format: "%.0f", stats.successRate * 100))%")
                StatBox(title: "Total Cost", value: "$\(String(format: "%.4f", stats.totalCost))")
                if let avgDuration = stats.averageDuration {
                    StatBox(title: "Avg Duration", value: "\(String(format: "%.1f", avgDuration))s")
                }
            }
        }
    }

    @ViewBuilder
    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Runs")
                    .font(.headline)
                Spacer()
                Button("View All") {
                    showingRunHistory = true
                }
                .buttonStyle(.link)
            }

            if let runs = try? store.listRuns(workflowName: workflowName, limit: 3) {
                if runs.isEmpty {
                    Text("No runs yet")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(runs, id: \.id) { run in
                        RecentRunRow(run: run)
                    }
                }
            }
        }
    }

    private func loadWorkflow() {
        do {
            workflow = try store.load(name: workflowName)
            workflowInfo = try store.getWorkflowInfo(name: workflowName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleEnabled() {
        do {
            if launchAgent.isInstalled(workflowName: workflowName) {
                try launchAgent.uninstall(workflowName: workflowName)
            } else if let workflow = workflow {
                try launchAgent.install(workflow: workflow)
            }
            loadWorkflow()
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.medium)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

struct RecentRunRow: View {
    let run: WorkflowRun

    private var statusColor: Color {
        switch run.status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .orange
        case .cancelled: return .gray
        case .pending: return .secondary
        }
    }

    private var statusIcon: String {
        switch run.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "play.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .pending: return "circle"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.id.prefix(8))
                    .font(.caption)
                    .fontWeight(.medium)

                Text(run.startTime, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(String(format: "%.4f", run.totalCost))")
                    .font(.caption)

                if let duration = run.duration {
                    Text("\(String(format: "%.1f", duration))s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
