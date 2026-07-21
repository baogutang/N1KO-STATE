// N1KO modification notice: process-tree and tmux focus semantics are adapted
// from Ping Island v0.26.0. N1KO keeps this as an on-demand public-process API
// query; it does not start a second watcher or use private window-server APIs.

import Foundation
import N1KOAgentCore

struct AgentProcessRecord: Sendable {
    let pid: Int
    let parentPID: Int
    let command: String
    let tty: String?
}

struct AgentProcessTreeBuilder: Sendable {
    static let shared = AgentProcessTreeBuilder()

    func buildTree() -> [Int: AgentProcessRecord] {
        guard let output = Self.run("/bin/ps", arguments: ["-eo", "pid,ppid,tty,args"]) else {
            return [:]
        }
        var tree: [Int: AgentProcessRecord] = [:]
        for line in output.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 4,
                  let pid = Int(parts[0]),
                  let parentPID = Int(parts[1]) else { continue }
            let tty = parts[2] == "??" ? nil : String(parts[2])
            tree[pid] = AgentProcessRecord(
                pid: pid,
                parentPID: parentPID,
                command: parts[3...].joined(separator: " "),
                tty: tty
            )
        }
        return tree
    }

    func isInTMUX(pid: Int, tree: [Int: AgentProcessRecord]) -> Bool {
        var current = pid
        for _ in 0..<20 {
            guard current > 1, let record = tree[current] else { break }
            if record.command.lowercased().contains("tmux") { return true }
            current = record.parentPID
        }
        return false
    }

    func isDescendant(pid: Int, of ancestorPID: Int, tree: [Int: AgentProcessRecord]) -> Bool {
        var current = pid
        for _ in 0..<50 {
            if current == ancestorPID { return true }
            guard current > 1, let record = tree[current] else { break }
            current = record.parentPID
        }
        return false
    }

    func terminalPID(forProcess pid: Int, tree: [Int: AgentProcessRecord]) -> Int? {
        var current = pid
        for _ in 0..<20 {
            guard current > 1, let record = tree[current] else { break }
            if TerminalAppRegistry.isTerminal(record.command) { return current }
            current = record.parentPID
        }
        return nil
    }

    func terminalPID(forTTY tty: String, tree: [Int: AgentProcessRecord]) -> Int? {
        let normalized = tty.replacingOccurrences(of: "/dev/", with: "")
        let candidates = tree.values
            .filter { $0.tty == normalized }
            .sorted { processScore($0.command) > processScore($1.command) }
        return candidates.lazy.compactMap { terminalPID(forProcess: $0.pid, tree: tree) }.first
    }

    func activeTMUXPaneContains(pid: Int, tree: [Int: AgentProcessRecord]) -> Bool {
        guard let executable = AgentTMUXExecutableResolver.resolve(),
              let panes = Self.run(executable.path, arguments: [
                  "list-panes", "-a", "-F",
                  "#{session_name}:#{window_index}.#{pane_index}\t#{pane_pid}"
              ]) else { return false }

        var sessionTarget: String?
        for line in panes.components(separatedBy: CharacterSet.newlines) {
            let values = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard values.count == 2, let panePID = Int(values[1]) else { continue }
            if isDescendant(pid: pid, of: panePID, tree: tree) {
                sessionTarget = values[0]
                break
            }
        }
        guard let sessionTarget,
              let active = Self.run(executable.path, arguments: [
                  "display-message", "-p", "#{session_name}:#{window_index}.#{pane_index}"
              ])?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return sessionTarget == active
    }

    private func processScore(_ command: String) -> Int {
        let value = command.lowercased()
        if value.contains("zsh") || value.contains("bash") || value.contains("fish") || value.contains("/sh") {
            return 4
        }
        if value.contains("login") { return 3 }
        if value.contains("claude") || value.contains("codex") { return 2 }
        return 1
    }

    private static func run(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
