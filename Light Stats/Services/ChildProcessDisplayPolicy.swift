//
//  ChildProcessDisplayPolicy.swift
//  Light Stats
//
//  Pure transform from a sampled process to the line an expanded app row shows.
//

import Foundation

/// Names the members of one app group for the expanded detail list.
///
/// A member is told apart by the innermost `.app` it lives in. Every helper of an application
/// shares that application's outer bundle name, so only a nested helper bundle —
/// `…/Contents/Frameworks/Figma Helper (Renderer).app/…` — names it.
/// A helper that lives directly inside its host, with no nested bundle of its own,
/// is named by its executable instead.
nonisolated enum ChildProcessDisplayPolicy {

    /// One detail line: what to show, and what the tooltip holds.
    struct Entry: Sendable {
        let pid: pid_t
        let label: String
        let detail: String
        let memoryBytes: UInt64?
        /// True when another member shares this label, so the pid is the only discriminator.
        let showsPID: Bool
    }

    static func entries(for processes: [TopProcessInfo], ownerName: String? = nil) -> [Entry] {
        var occurrences: [String: Int] = [:]
        var labels: [String] = []
        labels.reserveCapacity(processes.count)
        for process in processes {
            let label = label(forCommand: process.command, ownerName: ownerName)
            labels.append(label)
            occurrences[label, default: 0] += 1
        }
        return zip(processes, labels).map { process, label in
            Entry(
                pid: process.pid,
                label: label,
                detail: process.command,
                memoryBytes: process.memoryBytes,
                showsPID: (occurrences[label] ?? 0) > 1
            )
        }
    }

    /// The group's own process first, then members by memory. The owning process is what the
    /// row's count and close button refer to, so it must not be missing from its own detail list.
    static func orderedMembers(_ members: [TopProcessInfo], ownerPID: pid_t) -> [TopProcessInfo] {
        let ordered = members.sorted { lhs, rhs in
            if lhs.memoryBytes == rhs.memoryBytes { return lhs.pid < rhs.pid }
            return (lhs.memoryBytes ?? 0) > (rhs.memoryBytes ?? 0)
        }
        guard let ownerIndex = ordered.firstIndex(where: { $0.pid == ownerPID }) else { return ordered }
        var ownerFirst = ordered
        ownerFirst.insert(ownerFirst.remove(at: ownerIndex), at: 0)
        return ownerFirst
    }

    static func label(for process: TopProcessInfo, ownerName: String? = nil) -> String {
        label(forCommand: process.command, ownerName: ownerName)
    }

    static func label(forCommand command: String, ownerName: String? = nil) -> String {
        let bundles = appBundleNames(in: command)
        if bundles.count > 1, let innermost = bundles.last {
            return strippingOwnerPrefix(innermost, ownerName: ownerName)
        }
        let name = executableName(forCommand: command)
        return name.isEmpty ? command : strippingOwnerPrefix(name, ownerName: ownerName)
    }

    /// The rules in `shouldShowProcess` match an executable name, never a full path.
    static func executableName(forCommand command: String) -> String {
        guard let slash = command.lastIndex(of: "/") else { return command }
        return String(command[command.index(after: slash)...])
    }

    private static func appBundleNames(in command: String) -> [String] {
        command
            .split(separator: "/")
            .filter { $0.hasSuffix(".app") }
            .map { String($0.dropLast(4)) }
    }

    /// Every helper repeats its application's name, and that prefix alone can use up the
    /// column, so the part that names the member is what is left after it.
    private static func strippingOwnerPrefix(_ name: String, ownerName: String?) -> String {
        guard let ownerName, !ownerName.isEmpty else { return name }
        let prefix = ownerName + " "
        guard name.count > prefix.count, name.lowercased().hasPrefix(prefix.lowercased()) else {
            return name
        }
        return String(name.dropFirst(prefix.count))
    }
}
