//
//  PanelCloseClassificationTests.swift
//  LightStatsTests
//
//  「无理由失焦」只有在真的没有理由时才算异常：面板为自家窗口让出 key 属于可解释的一类。
//

import XCTest
@testable import Light_Stats

final class PanelCloseClassificationTests: XCTestCase {

    // 产品规则：焦点落在自家设置 / 关于 / 弹窗上，不算 unexpectedResign。
    func testOwnWindowTakingKeyIsNotReportedAsUnexpected() {
        for role in [PanelKeyWindowRole.settings, .about, .alert] {
            XCTAssertEqual(
                classify(reason: .resignKey, role: role),
                .selfWindowTookKey,
                "\(role.rawValue) 拿走 key 时面板是有理由关闭的"
            )
        }
    }

    func testUnexpectedResignIsReservedForAnUnaccountedFocusLoss() {
        XCTAssertEqual(classify(reason: .resignKey, role: .none), .unexpectedResign)
        XCTAssertEqual(classify(reason: .resignKey, role: .other), .unexpectedResign)
    }

    func testPanelHoldingKeyIsNotTreatedAsAnotherWindowStealingIt() {
        XCTAssertEqual(
            classify(reason: .resignKey, role: .panel),
            .unexpectedResign,
            "面板自己就是 key 窗口时，不能拿它当「自家窗口抢走 key」的解释"
        )
    }

    func testOutsideClickIsStillExternalClick() {
        XCTAssertEqual(classify(reason: .resignKey, role: .none, recentOutsideClick: true), .externalClick)
        XCTAssertEqual(
            classify(reason: .resignKey, role: .settings, recentOutsideClick: true),
            .selfWindowTookKey,
            "自家窗口拿走 key 的证据比 0.25 秒内的鼠标点击更具体"
        )
    }

    func testTerminationTargetGrabbingFocusStaysExpected() {
        XCTAssertEqual(
            classify(reason: .resignKey, role: .none, terminationInFlight: true, matchesTarget: true),
            .expectedFocusGrab
        )
        XCTAssertEqual(
            classify(reason: .resignKey, role: .none, terminationInFlight: true, matchesTarget: false),
            .unexpectedResign
        )
        XCTAssertEqual(
            classify(reason: .resignKey, role: .settings, terminationInFlight: true, matchesTarget: false),
            .selfWindowTookKey,
            "目标应用没抢焦点，但自家窗口确实拿到 key —— 这仍然是有解释的"
        )
    }

    func testMouseAndManualDismissalsAreUnchanged() {
        XCTAssertEqual(classify(reason: .globalMouseDown, role: .other), .externalClick)
        XCTAssertEqual(classify(reason: .localMouseDown, role: .other), .externalClick)
        XCTAssertEqual(classify(reason: .resignActive, role: .other), .externalClick)
        XCTAssertEqual(classify(reason: .statusItemToggle, role: .other), .manual)
        XCTAssertEqual(classify(reason: .hotkeyToggle, role: .other), .manual)
        XCTAssertEqual(classify(reason: .externalRequest, role: .other), .manual)
    }

    // MARK: - Key window role

    func testKeyWindowRoleResolution() {
        XCTAssertEqual(role(className: nil), .none, "没有 key window")
        XCTAssertEqual(role(className: "KeyablePanel", isOwnedPanel: true), .panel)
        XCTAssertEqual(role(className: "_NSAlertPanel", isModal: true), .alert)
        XCTAssertEqual(role(className: "NSWindow", isModal: true), .alert, "模态窗口一律算弹窗")
        XCTAssertEqual(role(className: "AppKitWindow", identifier: "com_apple_SwiftUI_Settings_window"), .settings)
        XCTAssertEqual(role(className: "NSWindow", identifier: "LightStatsAbout"), .about)
        XCTAssertEqual(role(className: "NSWindow"), .other)
    }

    func testOwnWindowRolesAreFlaggedForTheRecord() {
        XCTAssertTrue(PanelKeyWindowRole.panel.isOwnWindow)
        XCTAssertTrue(PanelKeyWindowRole.settings.isOwnWindow)
        XCTAssertTrue(PanelKeyWindowRole.about.isOwnWindow)
        XCTAssertTrue(PanelKeyWindowRole.alert.isOwnWindow)
        XCTAssertFalse(PanelKeyWindowRole.none.isOwnWindow)
        XCTAssertFalse(PanelKeyWindowRole.other.isOwnWindow)
    }

    // MARK: - Helpers

    private func classify(
        reason: PanelDismissReason,
        role: PanelKeyWindowRole,
        recentOutsideClick: Bool = false,
        terminationInFlight: Bool = false,
        matchesTarget: Bool = false
    ) -> PanelCloseClassification {
        PanelCloseClassification.classify(
            reason: reason,
            keyWindowRole: role,
            recentOutsideClick: recentOutsideClick,
            terminationInFlight: terminationInFlight,
            frontmostMatchesTerminationTarget: matchesTarget
        )
    }

    private func role(
        className: String?,
        identifier: String? = nil,
        isModal: Bool = false,
        isOwnedPanel: Bool = false
    ) -> PanelKeyWindowRole {
        PanelKeyWindowRole.resolve(
            className: className,
            identifier: identifier,
            isModal: isModal,
            isOwnedPanel: isOwnedPanel
        )
    }
}
