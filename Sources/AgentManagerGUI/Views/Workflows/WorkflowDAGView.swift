import SwiftUI
import AgentManagerCore

struct WorkflowDAGView: View {
    let workflow: Workflow
    var jobStatuses: [String: JobStatus]?

    @State private var nodePositions: [String: CGPoint] = [:]

    var body: some View {
        GeometryReader { geometry in
            let positions = calculatePositions(in: geometry.size)

            ZStack {
                // Draw edges
                ForEach(Array(workflow.jobs.keys), id: \.self) { jobName in
                    if let job = workflow.jobs[jobName],
                       let needs = job.needs {
                        ForEach(needs, id: \.self) { dependency in
                            if let fromPos = positions[dependency],
                               let toPos = positions[jobName] {
                                EdgeView(from: fromPos, to: toPos)
                            }
                        }
                    }
                }

                // Draw nodes
                ForEach(Array(positions.keys), id: \.self) { jobName in
                    if let position = positions[jobName] {
                        JobNodeView(
                            name: jobName,
                            job: workflow.jobs[jobName]!,
                            status: jobStatuses?[jobName]
                        )
                        .position(position)
                    }
                }
            }
        }
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private func calculatePositions(in size: CGSize) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]

        // Group jobs by their depth (distance from root)
        var depths: [String: Int] = [:]

        // BFS to calculate depths
        var queue: [(String, Int)] = []

        // Start with root jobs (no dependencies)
        let rootJobs = workflow.rootJobs()
        for job in rootJobs {
            depths[job] = 0
            queue.append((job, 0))
        }

        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()

            // Find jobs that depend on current
            for (jobName, job) in workflow.jobs {
                if job.needs?.contains(current) == true {
                    let newDepth = depth + 1
                    if depths[jobName] == nil || depths[jobName]! < newDepth {
                        depths[jobName] = newDepth
                        queue.append((jobName, newDepth))
                    }
                }
            }
        }

        // Handle any remaining jobs (shouldn't happen if validation passes)
        for jobName in workflow.jobs.keys where depths[jobName] == nil {
            depths[jobName] = 0
        }

        // Group by depth level
        var levels: [Int: [String]] = [:]
        for (jobName, depth) in depths {
            levels[depth, default: []].append(jobName)
        }

        // Sort job names within each level for consistency
        for level in levels.keys {
            levels[level]?.sort()
        }

        // Calculate positions
        let maxLevel = levels.keys.max() ?? 0
        let levelWidth = size.width / CGFloat(maxLevel + 1)

        for (level, jobs) in levels {
            let levelHeight = size.height / CGFloat(jobs.count + 1)
            for (index, jobName) in jobs.enumerated() {
                let x = levelWidth * CGFloat(level) + levelWidth / 2
                let y = levelHeight * CGFloat(index + 1)
                positions[jobName] = CGPoint(x: x, y: y)
            }
        }

        return positions
    }
}

struct JobNodeView: View {
    let name: String
    let job: Job
    let status: JobStatus?

    private var statusColor: Color {
        guard let status = status else { return .secondary }
        switch status {
        case .pending: return .secondary
        case .running: return .orange
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .gray
        case .cancelled: return .gray
        }
    }

    private var statusIcon: String {
        guard let status = status else { return "circle" }
        switch status {
        case .pending: return "circle"
        case .running: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "forward.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if status != nil {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .font(.caption)
                }
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
            }

            if job.usesAgent, let agentName = job.agent {
                Text("agent: \(agentName)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let outputs = job.outputs, !outputs.isEmpty {
                Text("outputs: \(outputs.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor, lineWidth: status != nil ? 2 : 1)
        )
        .cornerRadius(8)
    }
}

struct EdgeView: View {
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        Path { path in
            path.move(to: from)

            // Bezier curve for nicer edges
            let midX = (from.x + to.x) / 2
            path.addCurve(
                to: to,
                control1: CGPoint(x: midX, y: from.y),
                control2: CGPoint(x: midX, y: to.y)
            )
        }
        .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}
