import SwiftUI
import AgentManagerCore

struct AgentRowView: View {
    let agentInfo: AgentInfo

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Text(agentInfo.statusIndicator)
                .foregroundColor(agentInfo.isEnabled ? .green : .secondary)
                .font(.caption)

            // Trigger icon
            Text(agentInfo.triggerIcon)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(agentInfo.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(agentInfo.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let lastRun = agentInfo.lastRun {
                    Text(formatRelativeDate(lastRun))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let tokens = agentInfo.lastRunTokensFormatted {
                    Text("\(tokens) tok")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
