//
//  DockPreviewRetention.swift
//  Light Stats
//

nonisolated struct DockPreviewRetention {
    private var lastInside: Double = -.infinity
    var exitDelay: Double = 0.25

    mutating func visit(at time: Double) { lastInside = time }
    mutating func reset() { lastInside = -.infinity }
    func shouldDismiss(at time: Double) -> Bool { time - lastInside >= exitDelay }
}
