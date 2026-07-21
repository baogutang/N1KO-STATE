// N1KO modification notice: adapted from Ping Island commit da130d6 for
// N1KO's single-owner integration, macOS 12 compatibility, or fullscreen boundary.

//
//  TerminalVisibilityDetector.swift
//  PingIsland
//
//  Detects if terminal windows are visible on current space
//

import AppKit
import CoreGraphics

struct TerminalVisibilityDetector {
    /// Check if any terminal window is visible on the current space
    static func isTerminalVisibleOnCurrentSpace() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue }

            if TerminalAppRegistry.isTerminal(ownerName) {
                return true
            }
        }

        return false
    }

    /// Check if the frontmost (active) application is a terminal
    static func isTerminalFrontmost() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }

        return TerminalAppRegistry.isTerminalBundle(bundleId)
    }

    /// Check if a tracked session is currently focused (user is looking at it)
    /// - Parameter sessionPid: The PID of the Claude process
    /// - Returns: true if the session's terminal is frontmost and (for tmux) the pane is active
    static func isSessionFocused(sessionPid: Int) async -> Bool {
        guard isTerminalFrontmost(),
              let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return false
        }
        return await Task.detached(priority: .utility) {
            let builder = AgentProcessTreeBuilder.shared
            let tree = builder.buildTree()
            guard !tree.isEmpty else { return false }
            if builder.isInTMUX(pid: sessionPid, tree: tree) {
                return builder.activeTMUXPaneContains(pid: sessionPid, tree: tree)
            }
            let record = tree[sessionPid]
            let terminalPID = record?.tty.flatMap {
                builder.terminalPID(forTTY: $0, tree: tree)
            } ?? builder.terminalPID(forProcess: sessionPid, tree: tree)
            return terminalPID == Int(frontmostPID)
        }.value
    }
}
