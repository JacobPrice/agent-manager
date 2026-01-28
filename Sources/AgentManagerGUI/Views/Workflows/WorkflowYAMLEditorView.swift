import SwiftUI
import AgentManagerCore

struct WorkflowYAMLEditorView: View {
    let workflowName: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var yamlContent: String = ""
    @State private var originalContent: String = ""
    @State private var errorMessage: String?
    @State private var validationError: String?
    @State private var isSaving = false

    private let store = WorkflowStore.shared

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Edit Workflow: \(workflowName)")
                    .font(.headline)

                Spacer()

                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveWorkflow()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || !hasChanges)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))

            Divider()

            // YAML Editor
            YAMLTextEditor(text: $yamlContent)
                .font(.system(.body, design: .monospaced))
                .onChange(of: yamlContent) { _, newValue in
                    validateYAML(newValue)
                }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding()
                .background(Color.red.opacity(0.1))
            }
        }
        .onAppear {
            loadWorkflow()
        }
    }

    private var hasChanges: Bool {
        yamlContent != originalContent
    }

    private func loadWorkflow() {
        do {
            let workflow = try store.load(name: workflowName)
            yamlContent = try workflow.toYAML()
            originalContent = yamlContent
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load workflow: \(error.localizedDescription)"
        }
    }

    private func validateYAML(_ content: String) {
        validationError = nil

        guard let data = content.data(using: .utf8) else {
            validationError = "Invalid text encoding"
            return
        }

        do {
            let workflow = try Workflow.load(from: data)
            try workflow.validate()
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func saveWorkflow() {
        guard let data = yamlContent.data(using: .utf8) else {
            errorMessage = "Invalid text encoding"
            return
        }

        isSaving = true
        errorMessage = nil

        do {
            let workflow = try Workflow.load(from: data)
            try workflow.validate()
            try store.save(workflow)
            originalContent = yamlContent
            onSave()
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
