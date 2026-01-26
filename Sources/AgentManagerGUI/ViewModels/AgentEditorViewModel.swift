import Foundation
import Combine
import AgentManagerCore
import Yams

@MainActor
class AgentEditorViewModel: ObservableObject {
    // Form fields
    @Published var name: String = ""
    @Published var description: String = ""
    @Published var triggerType: TriggerType = .manual
    @Published var scheduleHour: Int = 9
    @Published var scheduleMinute: Int = 0
    @Published var watchPath: String = ""
    @Published var workingDirectory: String = "~/"
    @Published var contextScript: String = ""
    @Published var prompt: String = ""
    @Published var allowedToolsText: String = ""
    @Published var maxTurns: Int = 10
    @Published var maxBudgetUSD: Double = 1.0

    // State
    @Published var originalAgent: Agent?
    @Published var hasUnsavedChanges = false
    @Published var errorMessage: String?
    @Published var yamlContent: String = ""
    @Published var isYAMLMode = false

    private let store = AgentStore.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupChangeTracking()
    }

    private func setupChangeTracking() {
        // Track changes to all form fields
        Publishers.CombineLatest4(
            $name, $description, $triggerType,
            Publishers.CombineLatest($scheduleHour, $scheduleMinute)
        )
        .dropFirst()
        .sink { [weak self] _ in self?.markChanged() }
        .store(in: &cancellables)

        Publishers.CombineLatest4(
            $watchPath, $workingDirectory, $contextScript, $prompt
        )
        .dropFirst()
        .sink { [weak self] _ in self?.markChanged() }
        .store(in: &cancellables)

        Publishers.CombineLatest3(
            $allowedToolsText,
            $maxTurns.map { String($0) },
            $maxBudgetUSD.map { String($0) }
        )
        .dropFirst()
        .sink { [weak self] _ in self?.markChanged() }
        .store(in: &cancellables)
    }

    private func markChanged() {
        hasUnsavedChanges = true
    }

    func loadAgent(name: String) {
        do {
            let agent = try store.load(name: name)
            populateFields(from: agent)
            originalAgent = agent
            hasUnsavedChanges = false
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load agent: \(error.localizedDescription)"
        }
    }

    private func populateFields(from agent: Agent) {
        name = agent.name
        description = agent.description
        triggerType = agent.trigger.type
        scheduleHour = agent.trigger.hour ?? 9
        scheduleMinute = agent.trigger.minute ?? 0
        watchPath = agent.trigger.watchPath ?? ""
        workingDirectory = agent.workingDirectory
        contextScript = agent.contextScript ?? ""
        prompt = agent.prompt
        allowedToolsText = agent.allowedTools.joined(separator: "\n")
        maxTurns = agent.maxTurns
        maxBudgetUSD = agent.maxBudgetUSD

        // Generate YAML
        if let yaml = try? agent.toYAML() {
            yamlContent = yaml
        }
    }

    func buildAgent() -> Agent {
        let trigger: Trigger
        switch triggerType {
        case .schedule:
            trigger = Trigger(type: .schedule, hour: scheduleHour, minute: scheduleMinute)
        case .fileWatch:
            trigger = Trigger(type: .fileWatch, watchPath: watchPath.isEmpty ? nil : watchPath)
        case .manual:
            trigger = Trigger(type: .manual)
        }

        let allowedTools = allowedToolsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return Agent(
            name: name,
            description: description,
            trigger: trigger,
            workingDirectory: workingDirectory,
            contextScript: contextScript.isEmpty ? nil : contextScript,
            prompt: prompt,
            allowedTools: allowedTools,
            maxTurns: maxTurns,
            maxBudgetUSD: maxBudgetUSD
        )
    }

    func save() -> Bool {
        errorMessage = nil

        // Validate name
        guard !name.isEmpty else {
            errorMessage = "Agent name cannot be empty"
            return false
        }

        guard name.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else {
            errorMessage = "Agent name can only contain letters, numbers, hyphens, and underscores"
            return false
        }

        let agent = buildAgent()

        do {
            // Handle rename case
            if let original = originalAgent, original.name != name {
                // Check if new name already exists
                if store.exists(name: name) {
                    errorMessage = "An agent named '\(name)' already exists"
                    return false
                }

                // Delete old agent
                try store.delete(name: original.name)

                // Uninstall old LaunchAgent if installed
                if LaunchAgentManager.shared.isInstalled(agentName: original.name) {
                    try LaunchAgentManager.shared.uninstall(agentName: original.name)
                }
            }

            // Save agent
            try store.save(agent)
            originalAgent = agent
            hasUnsavedChanges = false

            // Update YAML
            if let yaml = try? agent.toYAML() {
                yamlContent = yaml
            }

            return true
        } catch {
            errorMessage = "Failed to save agent: \(error.localizedDescription)"
            return false
        }
    }

    func revert() {
        if let agent = originalAgent {
            populateFields(from: agent)
            hasUnsavedChanges = false
        }
    }

    func updateFromYAML() -> Bool {
        do {
            let decoder = YAMLDecoder()
            let agent = try decoder.decode(Agent.self, from: yamlContent)
            populateFields(from: agent)
            hasUnsavedChanges = true
            return true
        } catch {
            errorMessage = "Invalid YAML: \(error.localizedDescription)"
            return false
        }
    }

    func updateYAMLFromForm() {
        let agent = buildAgent()
        if let yaml = try? agent.toYAML() {
            yamlContent = yaml
        }
    }
}
