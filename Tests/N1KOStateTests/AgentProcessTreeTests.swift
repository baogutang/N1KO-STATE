import Foundation
@testable import N1KOAgentCore
@testable import N1KOState
import XCTest

final class AgentProcessTreeTests: XCTestCase {
    func testProcessTreeResolvesTerminalAndTMUXAncestryWithoutPrivateAPIs() {
        let tree: [Int: AgentProcessRecord] = [
            100: AgentProcessRecord(pid: 100, parentPID: 1, command: "/Applications/iTerm.app/Contents/MacOS/iTerm2", tty: nil),
            110: AgentProcessRecord(pid: 110, parentPID: 100, command: "login -fp user", tty: "ttys001"),
            120: AgentProcessRecord(pid: 120, parentPID: 110, command: "tmux new-session", tty: "ttys001"),
            130: AgentProcessRecord(pid: 130, parentPID: 120, command: "claude", tty: "ttys002")
        ]
        let builder = AgentProcessTreeBuilder.shared
        XCTAssertTrue(builder.isDescendant(pid: 130, of: 100, tree: tree))
        XCTAssertTrue(builder.isInTMUX(pid: 130, tree: tree))
        XCTAssertEqual(builder.terminalPID(forProcess: 130, tree: tree), 100)
        XCTAssertEqual(builder.terminalPID(forTTY: "ttys001", tree: tree), 100)
    }

    func testTMUXResolverPrefersExplicitThenPath() {
        let explicit = AgentTMUXExecutableResolver.resolve(
            environment: ["N1KO_TMUX_PATH": "/custom/tmux", "PATH": "/bin"],
            isExecutable: { $0 == "/custom/tmux" }
        )
        XCTAssertEqual(explicit?.path, "/custom/tmux")

        let fromPath = AgentTMUXExecutableResolver.resolve(
            environment: ["PATH": "/first:/second"],
            isExecutable: { $0 == "/second/tmux" }
        )
        XCTAssertEqual(fromPath?.path, "/second/tmux")
    }
}
