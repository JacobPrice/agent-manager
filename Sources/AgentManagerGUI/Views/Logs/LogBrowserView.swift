import SwiftUI
import AgentManagerCore

struct LogBrowserView: View {
    let agentName: String

    @StateObject private var viewModel = LogBrowserViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAllConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Logs: \(agentName)")
                    .font(.headline)

                Spacer()

                if viewModel.selectedLog != nil {
                    Toggle(isOn: $viewModel.isFollowing) {
                        Label("Follow", systemImage: viewModel.isFollowing ? "eye.fill" : "eye")
                    }
                    .toggleStyle(.button)
                    .onChange(of: viewModel.isFollowing) { _, isFollowing in
                        if isFollowing {
                            viewModel.startFollowing()
                        } else {
                            viewModel.stopFollowing()
                        }
                    }
                }

                Button {
                    viewModel.loadLogs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")

                Menu {
                    Button(role: .destructive) {
                        showingDeleteAllConfirmation = true
                    } label: {
                        Label("Delete All Logs", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }

                Button("Close") {
                    viewModel.stopFollowing()
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Split view
            HSplitView {
                // Log list
                VStack(spacing: 0) {
                    List(selection: Binding(
                        get: { viewModel.selectedLog?.url },
                        set: { (url: URL?) in
                            if let url = url, let log = viewModel.logs.first(where: { $0.url == url }) {
                                viewModel.selectLog(log)
                            }
                        }
                    )) {
                        ForEach(viewModel.logs, id: \.url) { log in
                            LogRowView(entry: log)
                                .tag(log.url)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.deleteLog(log)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.inset)
                }
                .frame(minWidth: 200, idealWidth: 250)

                // Log viewer
                LogViewerView(content: viewModel.logContent, isFollowing: viewModel.isFollowing)
            }

            // Error bar
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(error)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.errorMessage = nil
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.1))
            }
        }
        .onAppear {
            viewModel.agentName = agentName
        }
        .onDisappear {
            viewModel.stopFollowing()
        }
        .alert("Delete All Logs?", isPresented: $showingDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                viewModel.deleteAllLogs()
            }
        } message: {
            Text("Are you sure you want to delete all logs for '\(agentName)'? This action cannot be undone.")
        }
    }
}

struct LogRowView: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.formattedDate)
                .font(.caption)
                .fontWeight(.medium)

            Text(entry.formattedSize)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}
