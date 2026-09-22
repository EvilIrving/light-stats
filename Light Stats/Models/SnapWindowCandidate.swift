//
//  SnapWindowCandidate.swift
//  Light Stats
//

import CoreGraphics

/// Everything the eligibility rules need to know about a window.
///
/// Passing a value instead of an `AXUIElement` is what makes the rules testable: the three-layer
/// filter is the difference between "snapping feels reliable" and "snapping grabs a
/// Chrome toolbar once in a while", and none of that judgment needs a live window to verify.
struct SnapWindowCandidate: Sendable, Hashable {

    var role: String?
    var subrole: String?
    var title: String?
    var bundleIdentifier: String?
    var executableName: String?
    var frame: CGRect?
    var isMinimized: Bool
    var isFullScreen: Bool

    init(
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        bundleIdentifier: String? = nil,
        executableName: String? = nil,
        frame: CGRect? = nil,
        isMinimized: Bool = false,
        isFullScreen: Bool = false
    ) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
    }
}
