import SwiftUI
import AgentManagerCore

struct WorkflowRunnerView: View {
    let workflow: Workflow

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = WorkflowRunnerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Main content
            HSplitView {
                // Left: DAG visualization
                VStack(alignment: .leading, spacing: 8) {
                    Text("Jobs")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    WorkflowDAGView(workflow: workflow, jobStatuses: viewModel.jobStatuses)
                        .frame(minWidth: 250)
                        .padding()
                }

                // Right: Output
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Output")
                            .font(.headline)
                        Spacer()
                        Button {
                            viewModel.clear()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.isRunning)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(viewModel.outputLines.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                        .id(index)
                                }
                            }
                            .padding()
                        }
                        .background(Color.black.opacity(0.05))
                        .onChange(of: viewModel.outputLines.count) { _, _ in
                            if let lastIndex = viewModel.outputLines.indices.last {
                                proxy.scrollTo(lastIndex, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(minWidth: 350)
            }

            Divider()

            // Footer with status
            footerView
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("Run Workflow: \(workflow.name)")
                .font(.headline)

            Spacer()

            Toggle("Dry Run", isOn: $viewModel.isDryRun)
                .toggleStyle(.switch)
                .disabled(viewModel.isRunning)

            Button {
                if viewModel.isRunning {
                    viewModel.stop()
                } else {
                    viewModel.run(workflow: workflow)
                }
            } label: {
                if viewModel.isRunning {
                    Label("Stop", systemImage: "stop.fill")
                } else {
                    Label("Run", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isRunning ? .red : .accentColor)

            Button("Close") {
                dismiss()
            }
            .disabled(viewModel.isRunning)
        }
        .padding()
    }

    @ViewBuilder
    private var footerView: some View {
        HStack {
            // Status
            if viewModel.isRunning {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Running...")
                    .foregroundColor(.secondary)
            } else if let run = viewModel.workflowRun {
                Image(systemName: run.status == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(run.status == .completed ? .green : .red)
                Text(run.status.rawValue.capitalized)

                Text("•")
                    .foregroundColor(.secondary)

                if let duration = run.duration {
                    Text("\(String(format: "%.1f", duration))s")
                        .foregroundColor(.secondary)
                }

                Text("•")
                    .foregroundColor(.secondary)

                Text("$\(String(format: "%.4f", run.totalCost))")
                    .foregroundColor(.secondary)

                Text("•")
                    .foregroundColor(.secondary)

                Text("\(run.completedJobCount)/\(run.jobResults.count) jobs")
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Error message
            if let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .foregroundColor(.orange)
                    .lineLimit(1)
            }
        }
        .padding()
    }
}
