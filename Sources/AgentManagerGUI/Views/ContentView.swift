import SwiftUI
import AgentManagerCore

// Wrapper to make Agent work with sheet(item:)
struct IdentifiableAgent: Identifiable {
    let id: String
    let agent: Agent

    init(_ agent: Agent) {
        self.id = agent.name
        self.agent = agent
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct ContentView: View {
    @StateObject private var listViewModel = AgentListViewModel()
    @State private var agentToRun: IdentifiableAgent?
    @State private var logBrowserAgentName: String?

    var body: some View {
        NavigationSplitView {
            AgentListView(viewModel: listViewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            if let selectedName = listViewModel.selectedAgentName {
                AgentDetailView(
                    agentName: selectedName,
                    onRun: { agent in
                        agentToRun = IdentifiableAgent(agent)
                    },
                    onViewLogs: {
                        logBrowserAgentName = selectedName
                    },
                    onSaved: {
                        listViewModel.loadAgents()
                    }
                )
                .id(selectedName)
            } else {
                EmptyStateView(
                    onCreate: {
                        if let name = listViewModel.createNewAgent() {
                            listViewModel.selectedAgentName = name
                        }
                    }
                )
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .sheet(item: $agentToRun) { item in
            RunnerView(agent: item.agent)
                .frame(minWidth: 600, minHeight: 400)
        }
        .sheet(item: $logBrowserAgentName) { name in
            LogBrowserView(agentName: name)
                .frame(minWidth: 700, minHeight: 500)
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewAgent)) { _ in
            if let name = listViewModel.createNewAgent() {
                listViewModel.selectedAgentName = name
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshAgents)) { _ in
            listViewModel.loadAgents()
        }
    }
}

struct EmptyStateView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Agent Selected")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Select an agent from the sidebar or create a new one")
                .font(.body)
                .foregroundColor(.secondary)

            Button(action: onCreate) {
                Label("New Agent", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
