//
//  PermissionGuideFlightTests.swift
//  Light Stats
//

import XCTest
@testable import Light_Stats

/// The guide card's flight, sampled as a value.
///
/// Nothing here hosts a window: the panel that plays these frames is AppKit and untested, so every
/// number a person can see while the card travels has to be pinned here instead.
final class PermissionGuideFlightTests: XCTestCase {

    private let anchor = CGRect(x: 1200, y: 900, width: 80, height: 24)
    private let docked = CGRect(x: 600, y: 180, width: 468, height: 104)

    private var flight: PermissionGuideFlight {
        PermissionGuideFlight(startFrame: anchor, endFrame: docked)
    }

    private func sample(_ progress: Double) -> PermissionGuideGeometry.Sample {
        PermissionGuideGeometry.sample(flight, atProgress: progress)
    }

    // MARK: - Timing

    func testEaseInOutRunsFromZeroToOneThroughTheMidpoint() {
        XCTAssertEqual(PermissionGuideGeometry.easeInOut(0), 0, accuracy: 1e-12)
        XCTAssertEqual(PermissionGuideGeometry.easeInOut(1), 1, accuracy: 1e-12)
        XCTAssertEqual(PermissionGuideGeometry.easeInOut(0.5), 0.5, accuracy: 1e-12,
                       "the two halves must meet at the midpoint")
        XCTAssertEqual(PermissionGuideGeometry.easeInOut(0.25), 0.0625, accuracy: 1e-12,
                       "ease-in means a quarter of the time covers far less than a quarter of the way")
    }

    func testEaseInOutIgnoresProgressOutsideTheFlight() {
        XCTAssertEqual(PermissionGuideGeometry.easeInOut(-3), 0, accuracy: 1e-12)
        XCTAssertEqual(PermissionGuideGeometry.easeInOut(9), 1, accuracy: 1e-12)
    }

    func testEaseInOutIsSymmetricAboutTheMidpoint() {
        for step in 0...10 {
            let t = Double(step) / 10
            let forward = PermissionGuideGeometry.easeInOut(t)
            let mirrored = PermissionGuideGeometry.easeInOut(1 - t)
            XCTAssertEqual(forward + mirrored, 1, accuracy: 1e-12,
                           "an ease-in-out that is not symmetric reads as a lurch at t=\(t)")
        }
    }

    // MARK: - Arrival spring

    func testSpringEnvelopeStartsAtZeroAndLandsExactlyOnTheTarget() {
        XCTAssertEqual(PermissionGuideGeometry.springEnvelope(0), 0, accuracy: 1e-12)
        XCTAssertEqual(PermissionGuideGeometry.springEnvelope(1), 1, accuracy: 1e-12,
                       "the last frame has to be the target, not a fraction above it")
    }

    func testSpringEnvelopeOvershootsBeforeItSettles() {
        let samples = (0...100).map { PermissionGuideGeometry.springEnvelope(Double($0) / 100) }
        let peak = samples.max() ?? 0
        XCTAssertGreaterThan(peak, 1.01,
                             "an underdamped arrival passes its target; a critically damped one stops dead")
        XCTAssertLessThan(peak, 1.1, "the overshoot is a settle, not a bounce off the screen")
        XCTAssertLessThan(PermissionGuideGeometry.springEnvelope(0.5), peak,
                          "the peak belongs to the second half of the flight")
    }

    // MARK: - The path

    func testCardStartsOnTheAnchorAndEndsInTheDock() {
        let start = sample(0).frame
        XCTAssertEqual(start.midX, anchor.midX, accuracy: 1e-9)
        XCTAssertEqual(start.midY, anchor.midY, accuracy: 1e-9)
        XCTAssertEqual(start.size.width, anchor.size.width, accuracy: 1e-9)

        let end = sample(1).frame
        XCTAssertEqual(end.origin.x, docked.origin.x, accuracy: 1e-9)
        XCTAssertEqual(end.origin.y, docked.origin.y, accuracy: 1e-9)
        XCTAssertEqual(end.size, docked.size)
    }

    func testPathArcsAboveTheStraightLineBetweenTheEndpoints() {
        let middle = sample(0.5).frame
        let chord = (anchor.midY + docked.midY) / 2
        XCTAssertGreaterThan(
            middle.midY,
            chord + PermissionGuideFlight.apexHeight / 2,
            "the card flies over the chord, not along it: a straight line between a button and a window reads as a slide"
        )
    }

    func testCardGrowsPastTheDockSizeAndSettlesBackIntoIt() {
        let widths = [0, 0.3, 0.55, 0.75, 1].map { sample($0).frame.width }
        XCTAssertEqual(widths.first ?? 0, anchor.width, accuracy: 1e-9)
        XCTAssertEqual(widths.last ?? 0, docked.width, accuracy: 1e-9)
        for (earlier, later) in zip(widths.prefix(4), widths.dropFirst().prefix(3)) {
            XCTAssertGreaterThan(later, earlier, "the card grows the whole way out; it never shrinks mid-flight")
        }
        XCTAssertGreaterThan(widths[3], widths[4],
                             "the arrival overshoot carries the card past its dock size, then it settles back")
    }

    func testCornerRadiusRunsFromTwelveToTwentyFour() {
        XCTAssertEqual(sample(0).cornerRadius, 12, accuracy: 1e-9)
        XCTAssertEqual(sample(0.5).cornerRadius, 18, accuracy: 1e-9)
        XCTAssertEqual(sample(1).cornerRadius, 24, accuracy: 1e-9)
    }

    func testShadowIsAbsentAtBothEndsAndStrongestHalfway() {
        XCTAssertEqual(sample(0).shadowOpacity, 0, accuracy: 1e-12)
        XCTAssertEqual(sample(0.5).shadowOpacity, 1, accuracy: 1e-12)
        XCTAssertEqual(sample(1).shadowOpacity, 0, accuracy: 1e-12,
                       "a card that keeps its flight shadow at rest looks permanently airborne")
    }

    func testReversedFlightSwapsTheEndpoints() {
        let reversed = flight.reversed()
        XCTAssertEqual(reversed.startFrame, docked)
        XCTAssertEqual(reversed.endFrame, anchor)
        XCTAssertEqual(reversed.duration, PermissionGuideFlight.reverseDuration)
        XCTAssertEqual(reversed.apexHeight, flight.apexHeight, "the way back is the same arc, backwards")
    }

    func testReversedFlightSamplesBackOntoTheAnchor() {
        let back = PermissionGuideGeometry.sample(flight.reversed(), atProgress: 1).frame
        XCTAssertEqual(back.midX, anchor.midX, accuracy: 1e-9)
        XCTAssertEqual(back.midY, anchor.midY, accuracy: 1e-9)
    }
}
