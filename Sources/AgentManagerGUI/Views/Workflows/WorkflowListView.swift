import SwiftUI
import AgentManagerCore

struct WorkflowListView: View {
    @ObservedObject var viewModel: WorkflowListViewModel
    @State private var showingDeleteConfirmation = false
    @State private var workflowToDelete: String?

    var body: some View {
        List(selection: $viewModel.selectedWorkflowName) {
            ForEach(viewModel.workflows, id: \.name) { workflowInfo in
                WorkflowRowView(workflowInfo: workflowInfo)
                    .tag(workflowInfo.name)
                    .contextMenu {
                        if workflowInfo.hasSchedule {
                            Button {
                                viewModel.toggleEnabled(name: workflowInfo.name)
                            } label: {
                                if workflowInfo.isEnabled {
                                    Label("Disable Schedule", systemImage: "stop.circle")
                                } else {
                                    Label("Enable Schedule", systemImage: "play.circle")
                                }
                            }
                            Divider()
                        }

                        Button(role: .destructive) {
                            workflowToDelete = workflowInfo.name
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Workflows")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let name = viewModel.createNewWorkflow() {
                        viewModel.selectedWorkflowName = name
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Workflow")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.loadWorkflows()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.workflows.isEmpty {
                ContentUnavailableView {
                    Label("No Workflows", systemImage: "flowchart")
                } description: {
                    Text("Create your first workflow to orchestrate agents")
                } actions: {
                    Button("New Workflow") {
                        if let name = viewModel.createNewWorkflow() {
                            viewModel.selectedWorkflowName = name
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .alert("Delete Workflow?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let name = workflowToDelete {
                    viewModel.deleteWorkflow(name: name)
                }
            }
        } message: {
            if let name = workflowToDelete {
                Text("Are you sure you want to delete '\(name)'? This action cannot be undone.")
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
}

struct WorkflowRowView: View {
    let workflowInfo: WorkflowInfo

    private var statusColor: Color {
        switch workflowInfo.lastRunStatus {
        case .completed: return .green
        case .failed: return .red
        case .running: return .orange
        case .cancelled: return .gray
        case .pending, .none: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(workflowInfo.isEnabled ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(workflowInfo.name)
                        .font(.headline)

                    Spacer()

                    // Schedule/manual indicator
                    if workflowInfo.hasSchedule {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Last run status
                    if let status = workflowInfo.lastRunStatusIcon {
                        Text(status)
                            .foregroundColor(statusColor)
                    }
                }

                if let description = workflowInfo.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text("\(workflowInfo.jobCount) jobs")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let stats = workflowInfo.stats, stats.totalRuns > 0 {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(stats.totalRuns) runs")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
