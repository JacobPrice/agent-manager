import SwiftUI
import AgentManagerCore

struct AgentYAMLEditorView: View {
    @ObservedObject var viewModel: AgentEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var localYAML: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("YAML Editor")
                    .font(.headline)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Apply") {
                    applyChanges()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Editor
            YAMLTextEditor(text: $localYAML)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(error)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
            }
        }
        .onAppear {
            viewModel.updateYAMLFromForm()
            localYAML = viewModel.yamlContent
        }
    }

    private func applyChanges() {
        viewModel.yamlContent = localYAML
        if viewModel.updateFromYAML() {
            dismiss()
        } else {
            errorMessage = viewModel.errorMessage
        }
    }
}
