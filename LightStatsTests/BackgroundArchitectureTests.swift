//
//  BackgroundArchitectureTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

@MainActor
final class BackgroundArchitectureTests: XCTestCase {
    private let panelSize = PopoverContentView.canvasSize
    private let naturalConfiguration = BackgroundSceneConfiguration(intensity: 0.4)

    func testSunGoldKeyframesAreDeterministic() throws {
        let definition = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .film))
        let firstFrame = definition.makeFrame(
            time: 0,
            size: panelSize,
            configuration: naturalConfiguration
        )
        let repeatedFrame = definition.makeFrame(
            time: 0,
            size: panelSize,
            configuration: naturalConfiguration
        )
        XCTAssertEqual(firstFrame, repeatedFrame)
        XCTAssertEqual(firstFrame.primitives.count, 13)

        let firstSun = try XCTUnwrap(radialLights(in: firstFrame).first)
        XCTAssertEqual(firstSun.center.x, 180, accuracy: 0.001)
        XCTAssertEqual(firstSun.center.y, 222.3, accuracy: 0.02)
        XCTAssertEqual(firstSun.intensity, 0.76, accuracy: 0.001)

        let quarterFrame = definition.makeFrame(
            time: SunGoldPhysics.orbitPeriod / 4,
            size: panelSize,
            configuration: naturalConfiguration
        )
        let quarterSun = try XCTUnwrap(radialLights(in: quarterFrame).first)
        XCTAssertGreaterThan(quarterSun.center.x, panelSize.width)
        XCTAssertNotEqual(firstFrame, quarterFrame)
    }

    func testInkNightKeyframesAreDeterministic() throws {
        let definition = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .noir))
        let firstFrame = definition.makeFrame(
            time: 0,
            size: panelSize,
            configuration: naturalConfiguration
        )
        let repeatedFrame = definition.makeFrame(
            time: 0,
            size: panelSize,
            configuration: naturalConfiguration
        )
        XCTAssertEqual(firstFrame, repeatedFrame)
        XCTAssertEqual(firstFrame.primitives.count, 15)

        let moonlight = try XCTUnwrap(projectedLights(in: firstFrame).first)
        XCTAssertEqual(moonlight.source.x, 180, accuracy: 0.001)
        XCTAssertLessThan(moonlight.source.y, 0)
        XCTAssertEqual(moonlight.target.y, panelSize.height * 1.12, accuracy: 0.001)

        let laterFrame = definition.makeFrame(
            time: 24,
            size: panelSize,
            configuration: naturalConfiguration
        )
        XCTAssertNotEqual(firstFrame, laterFrame)
    }

    func testPauseFreezesFrameAndResumeKeepsTimeContinuous() throws {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let tenSeconds = start.addingTimeInterval(10)
        let thirtySeconds = start.addingTimeInterval(30)
        let clock = BackgroundMotionClock(intensity: 0.4, startDate: start)
        let definition = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .film))

        let runningSample = clock.sample(at: tenSeconds)
        clock.setIntensity(0, at: tenSeconds)
        let pausedSample = clock.sample(at: thirtySeconds)
        XCTAssertTrue(pausedSample.isPaused)
        XCTAssertEqual(pausedSample.time, runningSample.time, accuracy: 0.000_001)
        XCTAssertEqual(pausedSample.intensity, runningSample.intensity, accuracy: 0.000_001)

        let runningFrame = definition.makeFrame(
            time: runningSample.time,
            size: panelSize,
            configuration: BackgroundSceneConfiguration(intensity: runningSample.intensity)
        )
        let pausedFrame = definition.makeFrame(
            time: pausedSample.time,
            size: panelSize,
            configuration: BackgroundSceneConfiguration(intensity: pausedSample.intensity)
        )
        XCTAssertEqual(runningFrame, pausedFrame)

        clock.setIntensity(0.4, at: thirtySeconds)
        let resumedSample = clock.sample(at: thirtySeconds.addingTimeInterval(5))
        XCTAssertFalse(resumedSample.isPaused)
        XCTAssertGreaterThan(resumedSample.time, pausedSample.time)
        XCTAssertEqual(resumedSample.time, 6.0576, accuracy: 0.000_1)
    }

    func testDynamicsLevelsReduceWallTimeMotionWithoutChangingOrbitGeometry() throws {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let levels = [0.2, 0.4, 0.65, 1.0]
        let sceneTimes = levels.map { intensity in
            let clock = BackgroundMotionClock(intensity: intensity, startDate: start)
            return clock.sample(at: start.addingTimeInterval(1)).time
        }
        for pair in zip(sceneTimes, sceneTimes.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }

        let sunGold = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .film))
        let initialSunFrame = sunGold.makeFrame(
            time: 0,
            size: panelSize,
            configuration: BackgroundSceneConfiguration(intensity: levels[0])
        )
        let initialSun = try XCTUnwrap(radialLights(in: initialSunFrame).first)
        let sunDisplacements = try zip(levels, sceneTimes).map { intensity, sceneTime in
            let frame = sunGold.makeFrame(
                time: sceneTime,
                size: panelSize,
                configuration: BackgroundSceneConfiguration(intensity: intensity)
            )
            let sun = try XCTUnwrap(radialLights(in: frame).first)
            return distance(from: initialSun.center, to: sun.center)
        }
        for pair in zip(sunDisplacements, sunDisplacements.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }

        let sameTimeLowFrame = sunGold.makeFrame(
            time: 4,
            size: panelSize,
            configuration: BackgroundSceneConfiguration(intensity: levels[0])
        )
        let sameTimeHighFrame = sunGold.makeFrame(
            time: 4,
            size: panelSize,
            configuration: BackgroundSceneConfiguration(intensity: levels[3])
        )
        XCTAssertEqual(sameTimeLowFrame, sameTimeHighFrame)
    }

    func testThemesAreIsolatedAtRegistrationBoundary() throws {
        let sunGold = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .film))
        let inkNight = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .noir))
        XCTAssertNotEqual(sunGold.identifier, inkNight.identifier)
        XCTAssertTrue(Set(sunGold.materialIdentifiers).isDisjoint(with: Set(inkNight.materialIdentifiers)))
        XCTAssertNil(BackgroundThemeRegistry.definition(for: .glass))
        XCTAssertNil(BackgroundThemeRegistry.definition(for: .bento))

        let sunFrame = sunGold.makeFrame(time: 12, size: panelSize, configuration: naturalConfiguration)
        let nightFrame = inkNight.makeFrame(time: 12, size: panelSize, configuration: naturalConfiguration)
        XCTAssertEqual(radialLights(in: sunFrame).count, 1)
        XCTAssertTrue(directionalLights(in: sunFrame).isEmpty)
        XCTAssertTrue(projectedLights(in: sunFrame).isEmpty)
        XCTAssertTrue(radialLights(in: nightFrame).isEmpty)
        XCTAssertTrue(directionalLights(in: nightFrame).isEmpty)
        XCTAssertEqual(projectedLights(in: nightFrame).count, 1)
        XCTAssertNotEqual(sunFrame, nightFrame)
    }

    func testMaximumDynamicsProducesVisibleMotion() throws {
        let configuration = BackgroundSceneConfiguration(intensity: 1)
        let sunGold = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .film))
        let firstSunFrame = sunGold.makeFrame(time: 0, size: panelSize, configuration: configuration)
        let nextSunFrame = sunGold.makeFrame(time: 1, size: panelSize, configuration: configuration)
        let firstSun = try XCTUnwrap(radialLights(in: firstSunFrame).first)
        let nextSun = try XCTUnwrap(radialLights(in: nextSunFrame).first)
        XCTAssertGreaterThan(distance(from: firstSun.center, to: nextSun.center), 70)

        let firstLeaves = softMasks(in: firstSunFrame).filter { $0.shape == .ellipse }
        let nextLeaves = softMasks(in: nextSunFrame).filter { $0.shape == .ellipse }
        let largestLeafDisplacement = zip(firstLeaves, nextLeaves).reduce(CGFloat.zero) { result, pair in
            max(result, distance(from: pair.0.center, to: pair.1.center))
        }
        XCTAssertGreaterThan(largestLeafDisplacement, 4)

        let inkNight = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .noir))
        let firstNightFrame = inkNight.makeFrame(time: 0, size: panelSize, configuration: configuration)
        let nextNightFrame = inkNight.makeFrame(time: 1, size: panelSize, configuration: configuration)
        let firstMoonlight = try XCTUnwrap(projectedLights(in: firstNightFrame).first)
        let nextMoonlight = try XCTUnwrap(projectedLights(in: nextNightFrame).first)
        XCTAssertGreaterThan(distance(from: firstMoonlight.source, to: nextMoonlight.source), 20)
        XCTAssertGreaterThan(distance(from: firstMoonlight.target, to: nextMoonlight.target), 40)

        let laterCloudFrame = inkNight.makeFrame(time: 3, size: panelSize, configuration: configuration)
        let firstClouds = softMasks(in: firstNightFrame).filter { $0.role == .lightOccluder }
        let laterClouds = softMasks(in: laterCloudFrame).filter { $0.role == .lightOccluder }
        let largestCloudDisplacement = zip(firstClouds, laterClouds).reduce(CGFloat.zero) { result, pair in
            max(result, distance(from: pair.0.center, to: pair.1.center))
        }
        XCTAssertGreaterThan(largestCloudDisplacement, 20)
    }

    func testThemePhysicsCloseTheirOrbitsAndPreserveProjectionLaws() {
        XCTAssertLessThanOrEqual(SunGoldPhysics.orbitPeriod, 30)
        XCTAssertLessThanOrEqual(InkNightPhysics.orbitPeriod, 30)

        let firstSolarState = SunGoldPhysics.solarState(time: 0, size: panelSize)
        let loopedSolarState = SunGoldPhysics.solarState(
            time: SunGoldPhysics.orbitPeriod,
            size: panelSize
        )
        XCTAssertEqual(firstSolarState.center.x, loopedSolarState.center.x, accuracy: 0.001)
        XCTAssertEqual(firstSolarState.center.y, loopedSolarState.center.y, accuracy: 0.001)

        let lunarState = InkNightPhysics.lunarState(time: 5, size: panelSize)
        let aperture = CGPoint(x: panelSize.width * 0.5, y: panelSize.height * 0.15)
        let sourceToAperture = CGVector(
            dx: aperture.x - lunarState.source.x,
            dy: aperture.y - lunarState.source.y
        )
        let sourceToTarget = CGVector(
            dx: lunarState.target.x - lunarState.source.x,
            dy: lunarState.target.y - lunarState.source.y
        )
        let crossProduct = sourceToAperture.dx * sourceToTarget.dy
            - sourceToAperture.dy * sourceToTarget.dx
        XCTAssertEqual(crossProduct, 0, accuracy: 0.01)
        XCTAssertGreaterThan(lunarState.targetWidth, lunarState.sourceWidth)
    }

    func testInkCloudsOccludeTheLightLayerInsteadOfPaintingOpaqueCover() throws {
        let definition = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .noir))
        let frame = definition.makeFrame(time: 11, size: panelSize, configuration: naturalConfiguration)
        let clouds = softMasks(in: frame).filter { $0.role == .lightOccluder }

        XCTAssertEqual(projectedLights(in: frame).count, 1)
        XCTAssertEqual(clouds.count, 12)
        XCTAssertGreaterThan(clouds.map(\.opacity).max() ?? 0, 0.80)
        XCTAssertLessThan(clouds.map(\.opacity).min() ?? 1, 0.60)
        XCTAssertTrue(clouds.allSatisfy { $0.bodyOpacity < $0.opacity })
        let distinctWidths = Set(clouds.map { Int($0.size.width.rounded()) })
        XCTAssertGreaterThanOrEqual(distinctWidths.count, 6)
    }

    func testInkCloudTransmissionFollowsBeerLambertLaw() {
        let thinTransmission = InkNightCloudPhysics.transmission(forOpticalDepth: 0.2)
        let denseTransmission = InkNightCloudPhysics.transmission(forOpticalDepth: 1.8)
        XCTAssertGreaterThan(thinTransmission, 0.70)
        XCTAssertLessThan(denseTransmission, 0.07)

        let lobeDepths = [0.25, 0.50, 0.75]
        let layeredTransmission = lobeDepths
            .map(InkNightCloudPhysics.transmission)
            .reduce(1, *)
        let combinedTransmission = InkNightCloudPhysics.transmission(
            forOpticalDepth: lobeDepths.reduce(0, +)
        )
        XCTAssertEqual(layeredTransmission, combinedTransmission, accuracy: 0.000_001)
    }

    func testSceneSubjectsRemainVisibleInPanelAndPreviewViewports() throws {
        let previewHeight: CGFloat = 320
        let previewSize = CGSize(
            width: previewHeight * panelSize.width / panelSize.height,
            height: previewHeight
        )
        let sizes = [panelSize, previewSize]
        let sunGold = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .film))
        let inkNight = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .noir))

        for size in sizes {
            for time in stride(from: 0.0, through: 120.0, by: 2.0) {
                let sunFrame = sunGold.makeFrame(
                    time: time,
                    size: size,
                    configuration: naturalConfiguration
                )
                let visibleTreeShadows = visibleSoftMasks(in: sunFrame, canvasSize: size)
                    .filter { $0.role == .surfaceShadow }
                XCTAssertGreaterThanOrEqual(visibleTreeShadows.count, 5)

                let nightFrame = inkNight.makeFrame(
                    time: time,
                    size: size,
                    configuration: naturalConfiguration
                )
                let visibleClouds = visibleSoftMasks(in: nightFrame, canvasSize: size)
                    .filter { $0.role == .lightOccluder }
                XCTAssertGreaterThanOrEqual(visibleClouds.count, 4)
            }
        }
    }

    func testDisablingGrainLeavesOtherMaterialsActive() throws {
        let definitions = [
            try XCTUnwrap(BackgroundThemeRegistry.definition(for: .film)),
            try XCTUnwrap(BackgroundThemeRegistry.definition(for: .noir))
        ]
        let configuration = BackgroundMaterialConfiguration(grainEnabled: false)

        for definition in definitions {
            let activeMaterials = definition.materialEffects.filter {
                $0.isEnabled(configuration: configuration)
            }
            XCTAssertEqual(activeMaterials.count, 1)
            let remainingMaterial = try XCTUnwrap(activeMaterials.first)
            XCTAssertTrue(remainingMaterial.id.contains("vignette"))
        }
    }

    func testGrainUsesHighResolutionSamplingForRetinaCaptures() {
        XCTAssertGreaterThanOrEqual(GrainTextureView.samplingScale, 4)
    }

    func testEveryRegisteredSceneCoversArbitraryCanvasSizesWithBoundedPrimitives() throws {
        let definitions = [
            try XCTUnwrap(BackgroundThemeRegistry.definition(for: .film)),
            try XCTUnwrap(BackgroundThemeRegistry.definition(for: .noir))
        ]
        let sizes = [
            CGSize(width: 160, height: 120),
            CGSize(width: 360, height: 780),
            CGSize(width: 900, height: 260)
        ]

        for definition in definitions {
            for size in sizes {
                let frame = definition.makeFrame(
                    time: 37,
                    size: size,
                    configuration: naturalConfiguration
                )
                guard case .colorFill = frame.primitives.first else {
                    XCTFail("Every scene must begin with a full-canvas color fill")
                    continue
                }
                XCTAssertLessThanOrEqual(frame.primitives.count, 16)
            }
        }
    }

    private func radialLights(
        in frame: BackgroundSceneFrame
    ) -> [BackgroundSceneFrame.RadialLight] {
        frame.primitives.compactMap { primitive in
            guard case let .radialLight(light) = primitive else { return nil }
            return light
        }
    }

    private func directionalLights(
        in frame: BackgroundSceneFrame
    ) -> [BackgroundSceneFrame.DirectionalLight] {
        frame.primitives.compactMap { primitive in
            guard case let .directionalLight(light) = primitive else { return nil }
            return light
        }
    }

    private func projectedLights(
        in frame: BackgroundSceneFrame
    ) -> [BackgroundSceneFrame.ProjectedLight] {
        frame.primitives.compactMap { primitive in
            guard case let .projectedLight(light) = primitive else { return nil }
            return light
        }
    }

    private func softMasks(
        in frame: BackgroundSceneFrame
    ) -> [BackgroundSceneFrame.SoftMask] {
        frame.primitives.compactMap { primitive in
            guard case let .softMask(mask) = primitive else { return nil }
            return mask
        }
    }

    private func visibleSoftMasks(
        in frame: BackgroundSceneFrame,
        canvasSize: CGSize
    ) -> [BackgroundSceneFrame.SoftMask] {
        let canvasBounds = CGRect(origin: .zero, size: canvasSize)
        return softMasks(in: frame).filter { mask in
            let halfWidth = mask.size.width / 2
            let halfHeight = mask.size.height / 2
            let extentX = abs(cos(mask.angle)) * halfWidth + abs(sin(mask.angle)) * halfHeight
            let extentY = abs(sin(mask.angle)) * halfWidth + abs(cos(mask.angle)) * halfHeight
            let maskBounds = CGRect(
                x: mask.center.x - extentX,
                y: mask.center.y - extentY,
                width: extentX * 2,
                height: extentY * 2
            )
            return canvasBounds.intersects(maskBounds)
        }
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}
