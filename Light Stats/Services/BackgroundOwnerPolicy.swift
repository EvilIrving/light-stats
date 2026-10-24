//
//  BackgroundOwnerPolicy.swift
//  Light Stats
//
//  Pure rules for naming the application behind a background process.
//

import Foundation

/// Finds the installed application behind a process that no running application claims.
///
/// A background process carries two usable identifiers: the bundle it lives in, and the label of
/// the launchd job that starts it. Neither names an application on its own — the job label adds a
/// role (`…mac.helper`, `…chargelimiter.daemon`) — so the identifier is offered to the resolver
/// first as-is, then with each trailing role removed.
///
/// The process's own bundle is the stronger evidence: a helper living inside
/// `/Applications/UURemote.app` declares `com.netease.uuremote` itself, while a privileged helper
/// installed outside every bundle has only its job label to go on.
nonisolated enum BackgroundOwnerPolicy {

    /// An installed application, whether or not it is running.
    struct Owner: Sendable, Equatable {
        let key: String
        let name: String
    }

    /// Trailing label components that name a job's role rather than a product.
    private static let jobSuffixes: Set<String> = [
        "helper", "daemon", "agent", "service", "xpcservice", "xpc",
        "network-extension", "systemextension", "appex", "plugin"
    ]

    /// Identifiers to ask about, strongest evidence first, without repeats.
    static func candidateIdentifiers(for process: TopProcessInfo, launchdLabel: String?) -> [String] {
        var identifiers: [String] = []
        if let bundleId = process.bundleInfo.bundleId, !bundleId.isEmpty {
            identifiers.append(bundleId)
        }
        if let launchdLabel, !launchdLabel.isEmpty {
            identifiers.append(launchdLabel)
        }
        var seen = Set<String>()
        return identifiers.flatMap(strippingJobSuffixes).filter { seen.insert($0).inserted }
    }

    /// An identifier followed by each variant with one more trailing job role removed.
    static func strippingJobSuffixes(_ identifier: String) -> [String] {
        var parts = identifier.split(separator: ".").map(String.init)
        var variants: [String] = []
        while parts.count > 1 {
            variants.append(parts.joined(separator: "."))
            guard let last = parts.last, jobSuffixes.contains(last.lowercased()) else { break }
            parts.removeLast()
        }
        return variants
    }

    /// The application to show the process under, or `nil` when nothing installed owns it.
    static func owner(
        for process: TopProcessInfo,
        launchdLabel: String?,
        resolve: (String) -> Owner?
    ) -> Owner? {
        for identifier in candidateIdentifiers(for: process, launchdLabel: launchdLabel) {
            guard let owner = resolve(identifier) else { continue }
            return owner
        }
        return nil
    }
}
