import XCTest
@testable import AgentManagerCore

final class AgentTests: XCTestCase {
    func testAgentTemplate() {
        let agent = Agent.template(name: "test-agent")

        XCTAssertEqual(agent.name, "test-agent")
        XCTAssertEqual(agent.trigger.type, .manual)
        XCTAssertEqual(agent.maxTurns, 10)
        XCTAssertEqual(agent.maxBudgetUSD, 1.0)
    }

    func testYAMLRoundTrip() throws {
        let agent = Agent(
            name: "test-agent",
            description: "A test agent",
            trigger: Trigger(type: .schedule, hour: 9, minute: 30),
            workingDirectory: "~/test",
            contextScript: "echo hello",
            prompt: "Do something",
            allowedTools: ["Read", "Write"],
            maxTurns: 5,
            maxBudgetUSD: 0.50
        )

        let yaml = try agent.toYAML()
        let decoded = try Agent.load(from: yaml.data(using: .utf8)!)

        XCTAssertEqual(decoded.name, agent.name)
        XCTAssertEqual(decoded.description, agent.description)
        XCTAssertEqual(decoded.trigger.type, agent.trigger.type)
        XCTAssertEqual(decoded.trigger.hour, agent.trigger.hour)
        XCTAssertEqual(decoded.trigger.minute, agent.trigger.minute)
        XCTAssertEqual(decoded.workingDirectory, agent.workingDirectory)
        XCTAssertEqual(decoded.contextScript, agent.contextScript)
        XCTAssertEqual(decoded.prompt, agent.prompt)
        XCTAssertEqual(decoded.allowedTools, agent.allowedTools)
        XCTAssertEqual(decoded.maxTurns, agent.maxTurns)
        XCTAssertEqual(decoded.maxBudgetUSD, agent.maxBudgetUSD)
    }

    func testExpandedWorkingDirectory() {
        let agent = Agent.template(name: "test")
        let expanded = agent.expandedWorkingDirectory

        XCTAssertFalse(expanded.hasPrefix("~/"))
        XCTAssertTrue(expanded.hasPrefix("/"))
    }
}
