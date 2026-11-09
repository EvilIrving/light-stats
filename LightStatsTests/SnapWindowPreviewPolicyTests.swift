//
//  SnapWindowPreviewPolicyTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

/// The window-preview group's gate, per surface.
///
/// Thumbnails and the ⌘Tab switcher ship; the Dock hover preview is still unfinished, so it stays
/// hidden and inert however a stored preference is set. Availability and the user's own switch are
/// two separate questions, and a surface needs both.
final class SnapWindowPreviewPolicyTests: XCTestCase {

    private func configuration(
        thumbnails: Bool = true,
        dockPreview: Bool = true,
        commandTab: Bool = true
    ) -> SnapConfiguration {
        var configuration = SnapConfiguration.default
        configuration.isWindowThumbnailsEnabled = thumbnails
        configuration.isDockPreviewEnabled = dockPreview
        configuration.isCommandTabPlusEnabled = commandTab
        return configuration
    }

    /// The shipped gate: exactly the two surfaces that are finished are offered.
    func testTheFinishedSurfacesAreAvailable() {
        XCTAssertTrue(SnapWindowPreviewPolicy.isAvailable(.thumbnails))
        XCTAssertTrue(SnapWindowPreviewPolicy.isAvailable(.commandTab))
        XCTAssertTrue(
            SnapWindowPreviewPolicy.hasAvailableSurface,
            "the settings group is drawn because at least one surface ships"
        )
    }

    /// The Dock hover preview is not finished, so its row is not drawn and its poll never starts —
    /// even though the stored preference defaults to on.
    func testTheDockHoverPreviewStaysHiddenAndInert() {
        XCTAssertFalse(SnapWindowPreviewPolicy.isAvailable(.dockPreview))
        XCTAssertFalse(
            SnapWindowPreviewPolicy.isActive(
                .dockPreview,
                configuration: configuration(),
                windowManagementEnabled: true
            ),
            "default-on Dock preview must not start itself while the surface is unfinished"
        )
    }

    /// The ⌘Tab switcher and thumbnails are only gated by the switches now — window management and
    /// the surface's own preference.
    func testTheShippingSurfacesFollowTheStoredPreferences() {
        XCTAssertTrue(
            SnapWindowPreviewPolicy.isActive(
                .commandTab, configuration: configuration(), windowManagementEnabled: true
            )
        )
        XCTAssertFalse(
            SnapWindowPreviewPolicy.isActive(
                .commandTab,
                configuration: configuration(commandTab: false),
                windowManagementEnabled: true
            ),
            "the user's own switch still turns the switcher off"
        )
        XCTAssertTrue(
            SnapWindowPreviewPolicy.isActive(
                .thumbnails, configuration: configuration(), windowManagementEnabled: true
            )
        )
        XCTAssertFalse(
            SnapWindowPreviewPolicy.isActive(
                .thumbnails,
                configuration: configuration(thumbnails: false),
                windowManagementEnabled: true
            )
        )
    }

    /// An injected availability still overrides the shipped gate in both directions, which is what
    /// makes the rule testable.
    func testAnInjectedAvailabilityOverridesTheShippedGate() {
        let all = configuration()
        for surface in SnapWindowPreviewPolicy.Surface.allCases {
            XCTAssertFalse(
                SnapWindowPreviewPolicy.isActive(
                    surface,
                    configuration: all,
                    windowManagementEnabled: true,
                    available: false
                ),
                "\(surface.rawValue) must not run when it is reported unavailable"
            )
        }
        XCTAssertTrue(
            SnapWindowPreviewPolicy.isActive(
                .dockPreview, configuration: all, windowManagementEnabled: true, available: true
            ),
            "the rule itself still allows a surface that is offered"
        )
    }

    func testWindowManagementStillOwnsTheWholeGroup() {
        XCTAssertFalse(
            SnapWindowPreviewPolicy.isActive(
                .commandTab, configuration: configuration(), windowManagementEnabled: false
            ),
            "the preview surfaces belong to window management and stop with it"
        )
        XCTAssertFalse(
            SnapWindowPreviewPolicy.isActive(
                .thumbnails, configuration: configuration(), windowManagementEnabled: false
            )
        )
    }
}
