//
//  SnapDropPolicy.swift
//  Light Stats
//

nonisolated enum SnapDropPolicy {
    static func target(
        islandOwnsDrop: Bool,
        islandTarget: SnapTarget?,
        edgeTarget: SnapTarget?
    ) -> SnapTarget? {
        // A gap in the island cancels the drop; it must never fall through to maximization.
        islandOwnsDrop ? islandTarget : edgeTarget
    }
}
