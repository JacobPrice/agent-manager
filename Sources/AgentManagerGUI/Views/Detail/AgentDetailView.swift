import SwiftUI
import AgentManagerCore

struct AgentDetailView: View {
    let agentName: String
    let onRun: (Agent) -> Void
    let onViewLogs: () -> Void
    let onSaved: () -> Void

    @StateObject private var viewModel = AgentEditorViewModel()
    @State private var showingYAMLEditor = false
    @State private var stats: AgentStats?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.name.isEmpty ? "New Agent" : viewModel.name)
                            .font(.title)
                            .fontWeight(.bold)

                        if !viewModel.description.isEmpty {
                            Text(viewModel.description)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Button {
                            onRun(viewModel.buildAgent())
                        } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        if viewModel.triggerType == .schedule {
                            Button {
                                toggleEnabled()
                            } label: {
                                if isEnabled {
                                    Label("Disable", systemImage: "stop.circle")
                                } else {
                                    Label("Enable", systemImage: "play.circle")
                                }
                            }
                        }
                    }
                }

                // Stats bar
                if let stats = stats, stats.runCount > 0 {
                    HStack(spacing: 24) {
                        StatItem(label: "Runs", value: "\(stats.runCount)")

                        if let lastTokens = stats.lastRunTokens {
                            StatItem(label: "Last Run", value: formatTokens(lastTokens))
                        }

                        if let avgTokens = stats.averageTokens {
                            StatItem(label: "Avg Tokens", value: formatTokens(avgTokens))
                        }

                        if stats.totalCost > 0 {
                            StatItem(label: "Total Cost", value: String(format: "$%.2f", stats.totalCost))
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }

                // Form
                AgentFormView(viewModel: viewModel)

                Spacer(minLength: 20)
            }
            .padding()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingYAMLEditor = true
                } label: {
                    Label("Edit YAML", systemImage: "doc.text")
                }
                .help("Edit YAML directly")

                Button {
                    onViewLogs()
                } label: {
                    Label("View Logs", systemImage: "doc.plaintext")
                }
                .help("View agent logs")
            }

            ToolbarItemGroup(placement: .confirmationAction) {
                if viewModel.hasUnsavedChanges {
                    Button("Revert") {
                        viewModel.revert()
                    }

                    Button("Save") {
                        if viewModel.save() {
                            onSaved()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $showingYAMLEditor) {
            AgentYAMLEditorView(viewModel: viewModel)
                .frame(minWidth: 600, minHeight: 500)
        }
        .onAppear {
            viewModel.loadAgent(name: agentName)
            loadStats()
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

    private var isEnabled: Bool {
        LaunchAgentManager.shared.isInstalled(agentName: agentName)
    }

    private func toggleEnabled() {
        do {
            let agent = viewModel.buildAgent()
            if isEnabled {
                try LaunchAgentManager.shared.uninstall(agentName: agentName)
            } else {
                try LaunchAgentManager.shared.install(agent: agent)
            }
        } catch {
            viewModel.errorMessage = "Failed to toggle agent: \(error.localizedDescription)"
        }
    }

    private func loadStats() {
        stats = try? StatsManager.shared.getStats(agentName: agentName)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
    }
}
