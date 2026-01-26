import Foundation
import Combine
import AgentManagerCore

@MainActor
class AgentListViewModel: ObservableObject {
    @Published var agents: [AgentInfo] = []
    @Published var selectedAgentName: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store = AgentStore.shared

    init() {
        loadAgents()
    }

    func loadAgents() {
        isLoading = true
        errorMessage = nil

        do {
            agents = try store.listAgentInfo()
        } catch {
            errorMessage = "Failed to load agents: \(error.localizedDescription)"
            agents = []
        }

        isLoading = false
    }

    func deleteAgent(name: String) {
        do {
            // Uninstall LaunchAgent if installed
            if LaunchAgentManager.shared.isInstalled(agentName: name) {
                try LaunchAgentManager.shared.uninstall(agentName: name)
            }

            // Delete agent file
            try store.delete(name: name)

            // Clear selection if deleted agent was selected
            if selectedAgentName == name {
                selectedAgentName = nil
            }

            loadAgents()
        } catch {
            errorMessage = "Failed to delete agent: \(error.localizedDescription)"
        }
    }

    func toggleEnabled(name: String) {
        do {
            let agent = try store.load(name: name)

            if LaunchAgentManager.shared.isInstalled(agentName: name) {
                try LaunchAgentManager.shared.uninstall(agentName: name)
            } else {
                try LaunchAgentManager.shared.install(agent: agent)
            }

            loadAgents()
        } catch {
            errorMessage = "Failed to toggle agent: \(error.localizedDescription)"
        }
    }

    func createNewAgent() -> String? {
        // Generate a unique name
        let baseName = "new-agent"
        var counter = 1
        var name = baseName

        while store.exists(name: name) {
            name = "\(baseName)-\(counter)"
            counter += 1
        }

        let newAgent = Agent.template(name: name)

        do {
            try store.save(newAgent)
            loadAgents()
            return name
        } catch {
            errorMessage = "Failed to create agent: \(error.localizedDescription)"
            return nil
        }
    }
}
