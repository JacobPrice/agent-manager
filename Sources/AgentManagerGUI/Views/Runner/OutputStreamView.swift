import SwiftUI

struct OutputStreamView: View {
    let lines: [String]
    let isRunning: Bool

    @State private var autoScroll = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                            .id(index)
                    }

                    if isRunning {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Running...")
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .id("running-indicator")
                    }

                    // Invisible anchor for scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: lines.count) { _, _ in
                if autoScroll {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                Toggle(isOn: $autoScroll) {
                    Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help(autoScroll ? "Auto-scroll enabled" : "Auto-scroll disabled")
                .padding(8)
            }
        }
        .overlay {
            if lines.isEmpty && !isRunning {
                ContentUnavailableView {
                    Label("No Output", systemImage: "terminal")
                } description: {
                    Text("Click Run to start the agent")
                }
            }
        }
    }
}
