import SwiftUI
import AgentManagerCore

struct AgentListView: View {
    @ObservedObject var viewModel: AgentListViewModel
    @State private var showingDeleteConfirmation = false
    @State private var agentToDelete: String?

    var body: some View {
        List(selection: $viewModel.selectedAgentName) {
            ForEach(viewModel.agents, id: \.name) { agentInfo in
                AgentRowView(agentInfo: agentInfo)
                    .tag(agentInfo.name)
                    .contextMenu {
                        Button {
                            viewModel.toggleEnabled(name: agentInfo.name)
                        } label: {
                            if agentInfo.isEnabled {
                                Label("Disable", systemImage: "stop.circle")
                            } else {
                                Label("Enable", systemImage: "play.circle")
                            }
                        }
                        .disabled(agentInfo.triggerType != .schedule)

                        Divider()

                        Button(role: .destructive) {
                            agentToDelete = agentInfo.name
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Agents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let name = viewModel.createNewAgent() {
                        viewModel.selectedAgentName = name
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Agent")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.loadAgents()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.agents.isEmpty {
                ContentUnavailableView {
                    Label("No Agents", systemImage: "cpu")
                } description: {
                    Text("Create your first agent to get started")
                } actions: {
                    Button("New Agent") {
                        if let name = viewModel.createNewAgent() {
                            viewModel.selectedAgentName = name
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .alert("Delete Agent?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let name = agentToDelete {
                    viewModel.deleteAgent(name: name)
                }
            }
        } message: {
            if let name = agentToDelete {
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
