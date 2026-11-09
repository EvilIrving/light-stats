//
//  TCCGrantWatchStateTests.swift
//  Light Stats
//

import XCTest
@testable import Light_Stats

/// The "has the user finished in System Settings?" heuristic, polled as a value.
///
/// The failure this suite exists for is the one a single-sample rule produced: any dip in the
/// Settings window count concluded the flow, so opening the deep link (which can replace the window),
/// clicking a sidebar row, or dismissing any sheet ended the guide before the user had touched the
/// list — silently for Accessibility, and as a "restart to begin" claim for Screen Recording.
final class TCCGrantWatchStateTests: XCTestCase {

    private let samples = TCCGrantWatchState.dismissalSamples

    /// One poll with the count and activity unchanged, repeated.
    private func observe(_ state: inout TCCGrantWatchState,
                         windowCount: Int,
                         isAppActive: Bool = false,
                         times: Int = 1) -> TCCGrantSignal? {
        var last: TCCGrantSignal?
        for _ in 0..<times {
            last = state.observe(windowCount: windowCount, isAppActive: isAppActive)
        }
        return last
    }

    // MARK: - The window count

    func testASingleDipIsNotADismissal() {
        var state = TCCGrantWatchState(windowCount: 2, isAppActive: false)
        XCTAssertNil(observe(&state, windowCount: 1),
                     "opening the deep link can replace the Settings window; one short sample is churn, not an answer")
    }

    func testADipThatHoldsIsADismissal() {
        var state = TCCGrantWatchState(windowCount: 2, isAppActive: false)
        observe(&state, windowCount: 1, times: samples - 1)
        XCTAssertEqual(observe(&state, windowCount: 1), .settingsDismissed)
    }

    func testADipThatRecoversWithinTheWindowIsForgotten() {
        var state = TCCGrantWatchState(windowCount: 2, isAppActive: false)
        observe(&state, windowCount: 1, times: samples - 1)
        XCTAssertNil(observe(&state, windowCount: 2), "the count came back; nothing concluded")
        XCTAssertNil(observe(&state, windowCount: 1),
                     "the streak restarts, so the guide cannot conclude on the tail of the earlier dip")
    }

    func testAGrowingCountRaisesThePeak() {
        var state = TCCGrantWatchState(windowCount: 1, isAppActive: false)
        XCTAssertNil(observe(&state, windowCount: 2), "the privacy sheet appearing is not a dismissal")
        observe(&state, windowCount: 1, times: samples - 1)
        XCTAssertEqual(observe(&state, windowCount: 1), .settingsDismissed,
                       "the sheet closing falls back to the peak the sheet itself raised")
    }

    func testAQuietCountNeverConcludes() {
        var state = TCCGrantWatchState(windowCount: 3, isAppActive: false)
        XCTAssertNil(observe(&state, windowCount: 3, times: samples * 4))
    }

    // MARK: - The app coming back

    func testStartingInTheForegroundDoesNotCountAsAReturn() {
        var state = TCCGrantWatchState(windowCount: 1, isAppActive: true)
        XCTAssertNil(observe(&state, windowCount: 1, isAppActive: true),
                     "the latch arms only on false → true, or the first tick would conclude the flow")
    }

    func testComingBackAfterBeingBackgroundedIsAConclusion() {
        var state = TCCGrantWatchState(windowCount: 1, isAppActive: true)
        XCTAssertNil(observe(&state, windowCount: 1, isAppActive: false))
        XCTAssertEqual(observe(&state, windowCount: 1, isAppActive: true), .appReactivated)
    }

    func testADismissalWinsOverAReturnInTheSamePoll() {
        var state = TCCGrantWatchState(windowCount: 2, isAppActive: false)
        observe(&state, windowCount: 1, times: samples - 1)
        XCTAssertEqual(observe(&state, windowCount: 1, isAppActive: true), .settingsDismissed,
                       "the sheet closing is the more specific fact")
    }
}
