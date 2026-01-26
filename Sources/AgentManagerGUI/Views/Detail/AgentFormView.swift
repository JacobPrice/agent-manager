import SwiftUI
import AgentManagerCore

struct AgentFormView: View {
    @ObservedObject var viewModel: AgentEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Basic Info
            GroupBox("Basic Information") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Name") {
                        TextField("agent-name", text: $viewModel.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Description") {
                        TextField("What this agent does", text: $viewModel.description)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Working Directory") {
                        TextField("~/projects/my-project", text: $viewModel.workingDirectory)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.vertical, 8)
            }

            // Trigger
            GroupBox("Trigger") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Type", selection: $viewModel.triggerType) {
                        Text("Manual").tag(TriggerType.manual)
                        Text("Schedule").tag(TriggerType.schedule)
                        Text("File Watch").tag(TriggerType.fileWatch)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch viewModel.triggerType {
                    case .schedule:
                        HStack {
                            Text("Run daily at")
                            Picker("Hour", selection: $viewModel.scheduleHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(String(format: "%02d", hour)).tag(hour)
                                }
                            }
                            .frame(width: 70)
                            Text(":")
                            Picker("Minute", selection: $viewModel.scheduleMinute) {
                                ForEach(0..<60, id: \.self) { minute in
                                    Text(String(format: "%02d", minute)).tag(minute)
                                }
                            }
                            .frame(width: 70)
                        }

                    case .fileWatch:
                        LabeledContent("Watch Path") {
                            TextField("~/Documents/watched-folder", text: $viewModel.watchPath)
                                .textFieldStyle(.roundedBorder)
                        }

                    case .manual:
                        Text("This agent will only run when manually triggered.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 8)
            }

            // Context Script
            GroupBox("Context Script") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shell script to gather context before running the agent")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $viewModel.contextScript)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80)
                        .border(Color.secondary.opacity(0.3))
                }
                .padding(.vertical, 8)
            }

            // Prompt
            GroupBox("Prompt") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions for the agent")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $viewModel.prompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .border(Color.secondary.opacity(0.3))
                }
                .padding(.vertical, 8)
            }

            // Allowed Tools
            GroupBox("Allowed Tools") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One tool per line (e.g., Read, Edit, Bash(git *))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $viewModel.allowedToolsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                        .border(Color.secondary.opacity(0.3))
                }
                .padding(.vertical, 8)
            }

            // Limits
            GroupBox("Limits") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Max Turns") {
                        Stepper(value: $viewModel.maxTurns, in: 1...100) {
                            Text("\(viewModel.maxTurns)")
                                .monospacedDigit()
                        }
                    }

                    LabeledContent("Max Budget (USD)") {
                        HStack {
                            Text("$")
                            TextField("1.00", value: $viewModel.maxBudgetUSD, format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}
