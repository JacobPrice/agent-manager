import SwiftUI

struct LogViewerView: View {
    let content: String
    let isFollowing: Bool

    @State private var autoScroll = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)

                    // Anchor for scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("log-bottom")
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: content) { _, _ in
                if isFollowing && autoScroll {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if isFollowing {
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
                if content.isEmpty {
                    ContentUnavailableView {
                        Label("No Log Selected", systemImage: "doc.plaintext")
                    } description: {
                        Text("Select a log from the list to view its contents")
                    }
                }
            }
        }
    }
}
