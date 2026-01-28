import SwiftUI
import AgentManagerCore

@MainActor
class WorkflowListViewModel: ObservableObject {
    @Published var workflows: [WorkflowInfo] = []
    @Published var selectedWorkflowName: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store = WorkflowStore.shared
    private let launchAgent = WorkflowLaunchAgentManager.shared

    init() {
        loadWorkflows()
    }

    func loadWorkflows() {
        isLoading = true
        errorMessage = nil

        do {
            workflows = try store.listWorkflowInfo()
        } catch {
            errorMessage = error.localizedDescription
            workflows = []
        }

        isLoading = false
    }

    func createNewWorkflow() -> String? {
        let baseName = "new-workflow"
        var name = baseName
        var counter = 1

        // Find unique name
        while store.exists(name: name) {
            counter += 1
            name = "\(baseName)-\(counter)"
        }

        // Create template workflow
        let workflow = Workflow.template(name: name)

        do {
            try store.save(workflow)
            loadWorkflows()
            return name
        } catch {
            errorMessage = "Failed to create workflow: \(error.localizedDescription)"
            return nil
        }
    }

    func deleteWorkflow(name: String) {
        do {
            // Disable if enabled
            if launchAgent.isInstalled(workflowName: name) {
                try launchAgent.uninstall(workflowName: name)
            }

            // Delete workflow
            try store.delete(name: name)

            // Clear selection if deleting selected
            if selectedWorkflowName == name {
                selectedWorkflowName = nil
            }

            loadWorkflows()
        } catch {
            errorMessage = "Failed to delete workflow: \(error.localizedDescription)"
        }
    }

    func toggleEnabled(name: String) {
        do {
            if launchAgent.isInstalled(workflowName: name) {
                try launchAgent.uninstall(workflowName: name)
            } else {
                let workflow = try store.load(name: name)
                try launchAgent.install(workflow: workflow)
            }
            loadWorkflows()
        } catch {
            errorMessage = "Failed to toggle workflow: \(error.localizedDescription)"
        }
    }
}
