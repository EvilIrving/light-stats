//
//  SnapWindowPreviewPolicyTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

/// The window-preview group ships hidden and inert: the three surfaces are not finished, so no
/// stored preference may start them.
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

    func testEverySurfaceStaysInertWhileTheGroupIsUnavailable() {
        let all = configuration()
        for surface in SnapWindowPreviewPolicy.Surface.allCases {
            XCTAssertFalse(
                SnapWindowPreviewPolicy.isActive(
                    surface,
                    configuration: all,
                    windowManagementEnabled: true,
                    available: false
                ),
                "\(surface.rawValue) must not run while the preview group is hidden"
            )
        }
    }

    /// The shipped constant is what production callers use, so it must be the hidden one.
    func testTheGroupIsUnavailableAsShipped() {
        XCTAssertFalse(
            SnapWindowPreviewPolicy.isAvailable,
            "the preview surfaces are not finished — removing the gate must be deliberate"
        )
        XCTAssertFalse(
            SnapWindowPreviewPolicy.isActive(
                .dockPreview,
                configuration: configuration(),
                windowManagementEnabled: true
            ),
            "default-on Dock preview must not start itself on a fresh install"
        )
    }

    func testEachSurfaceStillNeedsItsOwnSwitchWhenAvailable() {
        let onlyDock = configuration(thumbnails: false, commandTab: false)
        XCTAssertFalse(
            SnapWindowPreviewPolicy.isActive(
                .thumbnails, configuration: onlyDock, windowManagementEnabled: true, available: true
            )
        )
        XCTAssertTrue(
            SnapWindowPreviewPolicy.isActive(
                .dockPreview, configuration: onlyDock, windowManagementEnabled: true, available: true
            )
        )
        XCTAssertFalse(
            SnapWindowPreviewPolicy.isActive(
                .commandTab, configuration: onlyDock, windowManagementEnabled: true, available: true
            )
        )
    }

    func testWindowManagementStillOwnsTheWholeGroup() {
        XCTAssertFalse(
            SnapWindowPreviewPolicy.isActive(
                .dockPreview, configuration: configuration(), windowManagementEnabled: false, available: true
            ),
            "the preview surfaces belong to window management and stop with it"
        )
    }
}
