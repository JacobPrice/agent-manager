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

// Wrapper to make Workflow work with sheet(item:)
struct IdentifiableWorkflow: Identifiable {
    let id: String
    let workflow: Workflow

    init(_ workflow: Workflow) {
        self.id = workflow.name
        self.workflow = workflow
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

enum SidebarSection: String, CaseIterable {
    case agents = "Agents"
    case workflows = "Workflows"

    var icon: String {
        switch self {
        case .agents: return "cpu"
        case .workflows: return "flowchart"
        }
    }
}

struct ContentView: View {
    @StateObject private var agentListViewModel = AgentListViewModel()
    @StateObject private var workflowListViewModel = WorkflowListViewModel()

    @State private var selectedSection: SidebarSection = .workflows
    @State private var agentToRun: IdentifiableAgent?
    @State private var workflowToRun: IdentifiableWorkflow?
    @State private var logBrowserAgentName: String?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Section picker
                Picker("Section", selection: $selectedSection) {
                    ForEach(SidebarSection.allCases, id: \.self) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)

                Divider()

                // Section content
                switch selectedSection {
                case .agents:
                    AgentListView(viewModel: agentListViewModel)

                case .workflows:
                    WorkflowListView(viewModel: workflowListViewModel)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
        } detail: {
            switch selectedSection {
            case .agents:
                if let selectedName = agentListViewModel.selectedAgentName {
                    AgentDetailView(
                        agentName: selectedName,
                        onRun: { agent in
                            agentToRun = IdentifiableAgent(agent)
                        },
                        onViewLogs: {
                            logBrowserAgentName = selectedName
                        },
                        onSaved: {
                            agentListViewModel.loadAgents()
                        }
                    )
                    .id(selectedName)
                } else {
                    EmptyStateView(
                        title: "No Agent Selected",
                        description: "Select an agent from the sidebar or create a new one",
                        buttonTitle: "New Agent",
                        buttonIcon: "plus",
                        onCreate: {
                            if let name = agentListViewModel.createNewAgent() {
                                agentListViewModel.selectedAgentName = name
                            }
                        }
                    )
                }

            case .workflows:
                if let selectedName = workflowListViewModel.selectedWorkflowName {
                    WorkflowDetailView(
                        workflowName: selectedName,
                        onRun: { workflow in
                            workflowToRun = IdentifiableWorkflow(workflow)
                        },
                        onSaved: {
                            workflowListViewModel.loadWorkflows()
                        }
                    )
                    .id(selectedName)
                } else {
                    EmptyStateView(
                        title: "No Workflow Selected",
                        description: "Select a workflow from the sidebar or create a new one",
                        buttonTitle: "New Workflow",
                        buttonIcon: "plus",
                        onCreate: {
                            if let name = workflowListViewModel.createNewWorkflow() {
                                workflowListViewModel.selectedWorkflowName = name
                            }
                        }
                    )
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(item: $agentToRun) { item in
            RunnerView(agent: item.agent)
                .frame(minWidth: 600, minHeight: 400)
        }
        .sheet(item: $workflowToRun) { item in
            WorkflowRunnerView(workflow: item.workflow)
                .frame(minWidth: 800, minHeight: 500)
        }
        .sheet(item: $logBrowserAgentName) { name in
            LogBrowserView(agentName: name)
                .frame(minWidth: 700, minHeight: 500)
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewAgent)) { _ in
            selectedSection = .agents
            if let name = agentListViewModel.createNewAgent() {
                agentListViewModel.selectedAgentName = name
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshAgents)) { _ in
            agentListViewModel.loadAgents()
            workflowListViewModel.loadWorkflows()
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let description: String
    let buttonTitle: String
    let buttonIcon: String
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(title)
                .font(.title2)
                .foregroundColor(.secondary)

            Text(description)
                .font(.body)
                .foregroundColor(.secondary)

            Button(action: onCreate) {
                Label(buttonTitle, systemImage: buttonIcon)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
