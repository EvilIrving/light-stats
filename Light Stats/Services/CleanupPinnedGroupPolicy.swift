//
//  CleanupPinnedGroupPolicy.swift
//  Light Stats
//
//  Pure rules for the single Cleanup "pinned" batch-quit group.
//  Persistence and termination stay in AppMemoryManager / SettingsManager.
//

import Foundation

enum CleanupPinnedGroupPolicy {

    /// Prefer bundle id; fall back to bundle path. No key → cannot pin.
    static func memberKey(bundleIdentifier: String?, bundlePath: String?) -> String? {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }
        if let bundlePath, !bundlePath.isEmpty {
            return bundlePath
        }
        return nil
    }

    static func memberKey(for app: AppGroup) -> String? {
        memberKey(bundleIdentifier: app.bundleIdentifier, bundlePath: app.bundlePath)
    }

    /// Only terminable GUI app rows. Background / pinned stubs and non-terminable rows are refused.
    static func canPin(_ app: AppGroup) -> Bool {
        guard app.isTerminable else { return false }
        guard app.id != AppGroup.backgroundGroupId else { return false }
        guard app.id != AppGroup.pinnedGroupId else { return false }
        return memberKey(for: app) != nil
    }

    /// Drop payloads are untrusted: only accept keys that match a currently pin-eligible running app.
    static func validatedDropKey(
        _ payload: String,
        among runningApps: [AppGroup]
    ) -> String? {
        guard !payload.isEmpty else { return nil }
        for app in runningApps where canPin(app) {
            if memberKey(for: app) == payload {
                return payload
            }
        }
        return nil
    }

    /// Idempotent insert. Returns the new list and whether it changed.
    static func inserting(_ key: String, into pinnedKeys: [String]) -> (keys: [String], changed: Bool) {
        if pinnedKeys.contains(key) {
            return (pinnedKeys, false)
        }
        return (pinnedKeys + [key], true)
    }

    /// Remove one key. Missing key is a no-op.
    static func removing(_ key: String, from pinnedKeys: [String]) -> (keys: [String], changed: Bool) {
        let next = pinnedKeys.filter { $0 != key }
        return (next, next.count != pinnedKeys.count)
    }

    /// Split the memory-sorted app list into (top list without pinned members, running pinned members).
    /// Background stub stays in the top list; pinned members keep their relative memory order.
    static func partition(
        _ apps: [AppGroup],
        pinnedKeys: Set<String>
    ) -> (top: [AppGroup], pinnedMembers: [AppGroup]) {
        guard !pinnedKeys.isEmpty else {
            return (apps, [])
        }
        var top: [AppGroup] = []
        var pinnedMembers: [AppGroup] = []
        for app in apps {
            if app.id == AppGroup.backgroundGroupId || app.id == AppGroup.pinnedGroupId {
                top.append(app)
                continue
            }
            if let key = memberKey(for: app), pinnedKeys.contains(key), canPin(app) {
                pinnedMembers.append(app)
            } else {
                top.append(app)
            }
        }
        return (top, pinnedMembers)
    }

    /// Count currently running members only — also "how many this batch can quit".
    static func runningMemberCount(pinnedMembers: [AppGroup]) -> Int {
        pinnedMembers.count
    }

    /// Stable serial quit plan: skip already-gone rows; preserve list order.
    static func batchTerminationPlan(from pinnedMembers: [AppGroup]) -> [AppGroup] {
        pinnedMembers.filter(\.isTerminable)
    }
}
