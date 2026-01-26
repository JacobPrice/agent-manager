import SwiftUI
import AgentManagerCore

struct RunnerView: View {
    let agent: Agent

    @StateObject private var viewModel = AgentRunnerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Run Agent: \(agent.name)")
                    .font(.headline)

                Spacer()

                Toggle("Dry Run", isOn: $viewModel.isDryRun)
                    .toggleStyle(.checkbox)
                    .disabled(viewModel.isRunning)

                if viewModel.isRunning {
                    Button {
                        viewModel.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button {
                        viewModel.run(agent: agent)
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Close") {
                    viewModel.stop()
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Output
            OutputStreamView(lines: viewModel.outputLines, isRunning: viewModel.isRunning)

            // Status bar
            HStack {
                if viewModel.isRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Running...")
                        .foregroundColor(.secondary)
                } else if let result = viewModel.runResult {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                    Text(result.success ? "Completed" : "Failed")
                    Text("-")
                        .foregroundColor(.secondary)
                    Text(formatDuration(result.duration))
                        .foregroundColor(.secondary)
                    if let tokens = result.totalTokens {
                        Text("-")
                            .foregroundColor(.secondary)
                        Text("\(formatTokens(tokens)) tokens")
                            .foregroundColor(.secondary)
                    }
                    if let cost = result.cost {
                        Text(String(format: "($%.3f)", cost))
                            .foregroundColor(.secondary)
                    }
                    if result.dryRun {
                        Text("(Dry Run)")
                            .foregroundColor(.orange)
                    }
                } else if let error = viewModel.errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(error)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if !viewModel.outputLines.isEmpty {
                    Button {
                        viewModel.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}
