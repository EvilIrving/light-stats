//
//  BackgroundArchitectureTests.swift
//  Light Stats Tests
//

import XCTest
@testable import Light_Stats

@MainActor
final class BackgroundArchitectureTests: XCTestCase {
    private let panelSize = PopoverContentView.canvasSize
    private let naturalConfiguration = BackgroundSceneConfiguration(intensity: 0.4, sceneSeed: 7_301)

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
        XCTAssertEqual(firstFrame.primitives.count, 213)

        let firstSun = try XCTUnwrap(radialLights(in: firstFrame).first)
        XCTAssertGreaterThan(firstSun.center.x, -panelSize.width * 0.5)
        XCTAssertLessThan(firstSun.center.x, panelSize.width * 1.5)
        XCTAssertGreaterThan(firstSun.center.y, panelSize.height * 0.16)
        XCTAssertLessThan(firstSun.center.y, panelSize.height * 0.30)
        XCTAssertGreaterThan(firstSun.intensity, 0.35)
        XCTAssertLessThanOrEqual(firstSun.intensity, 0.88)

        let quarterFrame = definition.makeFrame(
            time: SunGoldPhysics.nominalTraversalDuration / 4,
            size: panelSize,
            configuration: naturalConfiguration
        )
        let quarterSun = try XCTUnwrap(radialLights(in: quarterFrame).first)
        XCTAssertGreaterThan(distance(from: firstSun.center, to: quarterSun.center), 40)
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
        XCTAssertGreaterThan(moonlight.source.x, panelSize.width * 0.10)
        XCTAssertLessThan(moonlight.source.x, panelSize.width * 0.90)
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
        let clock = BackgroundMotionClock(intensity: 0.4, startDate: start, sceneSeed: 91)
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
            configuration: BackgroundSceneConfiguration(
                intensity: runningSample.intensity,
                sceneSeed: runningSample.sceneSeed
            )
        )
        let pausedFrame = definition.makeFrame(
            time: pausedSample.time,
            size: panelSize,
            configuration: BackgroundSceneConfiguration(
                intensity: pausedSample.intensity,
                sceneSeed: pausedSample.sceneSeed
            )
        )
        XCTAssertEqual(runningFrame, pausedFrame)
        XCTAssertEqual(runningSample.sceneSeed, pausedSample.sceneSeed)

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
            let clock = BackgroundMotionClock(intensity: intensity, startDate: start, sceneSeed: 91)
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
        let firstSun = try XCTUnwrap(radialLights(in: firstSunFrame).first)
        let laterSuns = try (1...6).map { second in
            let frame = sunGold.makeFrame(
                time: TimeInterval(second),
                size: panelSize,
                configuration: configuration
            )
            return try XCTUnwrap(radialLights(in: frame).first)
        }
        let largestSunDisplacement = laterSuns.map {
            distance(from: firstSun.center, to: $0.center)
        }.max() ?? 0
        let largestSunlightChange = laterSuns.map {
            abs(firstSun.intensity - $0.intensity)
        }.max() ?? 0
        XCTAssertGreaterThan(largestSunDisplacement, 70)
        XCTAssertGreaterThan(largestSunlightChange, 0.05)

        let firstLeaves = softMasks(in: firstSunFrame).filter {
            $0.role == .surfaceShadow && $0.shape == .leaf
        }
        let nextSunFrame = sunGold.makeFrame(time: 1, size: panelSize, configuration: configuration)
        let nextLeaves = softMasks(in: nextSunFrame).filter {
            $0.role == .surfaceShadow && $0.shape == .leaf
        }
        let largestLeafDisplacement = zip(firstLeaves, nextLeaves).reduce(CGFloat.zero) { result, pair in
            max(result, distance(from: pair.0.center, to: pair.1.center))
        }
        XCTAssertGreaterThan(largestLeafDisplacement, 4)

        let inkNight = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .noir))
        let firstNightFrame = inkNight.makeFrame(time: 0, size: panelSize, configuration: configuration)
        let firstMoonlight = try XCTUnwrap(projectedLights(in: firstNightFrame).first)
        let laterMoonlights = try (1...8).map { second in
            let frame = inkNight.makeFrame(
                time: TimeInterval(second),
                size: panelSize,
                configuration: configuration
            )
            return try XCTUnwrap(projectedLights(in: frame).first)
        }
        let largestMoonSourceDisplacement = laterMoonlights.map {
            distance(from: firstMoonlight.source, to: $0.source)
        }.max() ?? 0
        let largestMoonTargetDisplacement = laterMoonlights.map {
            distance(from: firstMoonlight.target, to: $0.target)
        }.max() ?? 0
        let largestMoonlightChange = laterMoonlights.map {
            abs(firstMoonlight.intensity - $0.intensity)
        }.max() ?? 0
        XCTAssertGreaterThan(largestMoonSourceDisplacement, 20)
        XCTAssertGreaterThan(largestMoonTargetDisplacement, 40)
        XCTAssertGreaterThan(largestMoonlightChange, 0.02)

        let laterCloudFrame = inkNight.makeFrame(time: 3, size: panelSize, configuration: configuration)
        let firstClouds = softMasks(in: firstNightFrame).filter { $0.role == .lightOccluder }
        let laterClouds = softMasks(in: laterCloudFrame).filter { $0.role == .lightOccluder }
        let largestCloudDisplacement = zip(firstClouds, laterClouds).reduce(CGFloat.zero) { result, pair in
            max(result, distance(from: pair.0.center, to: pair.1.center))
        }
        XCTAssertGreaterThan(largestCloudDisplacement, 20)
    }

    func testThemePhysicsAvoidClosedLoopsAndPreserveProjectionLaws() {
        let seed: UInt64 = 7_301
        let firstSolarState = SunGoldPhysics.solarState(time: 0, size: panelSize, seed: seed)
        let laterSolarState = SunGoldPhysics.solarState(
            time: SunGoldPhysics.nominalTraversalDuration,
            size: panelSize,
            seed: seed
        )
        XCTAssertGreaterThan(distance(from: firstSolarState.center, to: laterSolarState.center), 1)
        XCTAssertNotEqual(firstSolarState.brightness, laterSolarState.brightness)

        let firstLunarState = InkNightPhysics.lunarState(time: 0, size: panelSize, seed: seed)
        let laterLunarState = InkNightPhysics.lunarState(
            time: InkNightPhysics.nominalTraversalDuration,
            size: panelSize,
            seed: seed
        )
        XCTAssertGreaterThan(distance(from: firstLunarState.source, to: laterLunarState.source), 1)
        XCTAssertNotEqual(firstLunarState.intensity, laterLunarState.intensity)

        let lunarState = InkNightPhysics.lunarState(time: 5, size: panelSize, seed: seed)
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

    func testNoiseChannelsAreContinuousSeededAndPhysicallyCoupled() {
        let seed: UInt64 = 7_301
        let firstNoise = CoherentNoise.fractal(at: 4.25, seed: seed, octaves: 4)
        let adjacentNoise = CoherentNoise.fractal(at: 4.251, seed: seed, octaves: 4)
        XCTAssertLessThan(abs(firstNoise - adjacentNoise), 0.01)
        XCTAssertEqual(firstNoise, CoherentNoise.fractal(at: 4.25, seed: seed, octaves: 4))
        XCTAssertNotEqual(firstNoise, CoherentNoise.fractal(at: 4.25, seed: seed + 1, octaves: 4))

        let solarTime = 8.0
        let solarState = SunGoldPhysics.solarState(time: solarTime, size: panelSize, seed: seed)
        let elevation = (0.285 - solarState.center.y / panelSize.height) / 0.11
        let expectedBrightness = (0.74 + Double(elevation) * 0.14)
            * SunGoldPhysics.apparentLightTransmission(at: solarTime, seed: seed)
        XCTAssertEqual(solarState.brightness, expectedBrightness, accuracy: 0.000_001)

        let lunarTime = 11.0
        let lunarState = InkNightPhysics.lunarState(time: lunarTime, size: panelSize, seed: seed)
        let propagationDistance = hypot(
            lunarState.target.x - lunarState.source.x,
            lunarState.target.y - lunarState.source.y
        )
        let referenceDistance = panelSize.height * 1.42
        let falloff = pow(referenceDistance / propagationDistance, 2)
        let expectedIntensity = 0.68 * min(max(falloff, 0.80), 1.04)
            * InkNightPhysics.apparentLightTransmission(at: lunarTime, seed: seed)
        XCTAssertEqual(lunarState.intensity, expectedIntensity, accuracy: 0.000_001)
    }

    func testSceneSeedChangesTheWeatherWithoutBreakingDeterminism() throws {
        let definition = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .film))
        let firstConfiguration = BackgroundSceneConfiguration(intensity: 0.4, sceneSeed: 11)
        let secondConfiguration = BackgroundSceneConfiguration(intensity: 0.4, sceneSeed: 12)
        let firstFrame = definition.makeFrame(time: 9, size: panelSize, configuration: firstConfiguration)
        let repeatedFrame = definition.makeFrame(time: 9, size: panelSize, configuration: firstConfiguration)
        let differentWeather = definition.makeFrame(time: 9, size: panelSize, configuration: secondConfiguration)
        XCTAssertEqual(firstFrame, repeatedFrame)
        XCTAssertNotEqual(firstFrame, differentWeather)
    }

    func testSunGoldUsesDenseShimmeringFoliageWithoutTrunkShapes() throws {
        let definition = try XCTUnwrap(BackgroundThemeRegistry.definition(for: .film))
        let firstFrame = definition.makeFrame(time: 0, size: panelSize, configuration: naturalConfiguration)
        let laterFrame = definition.makeFrame(time: 2, size: panelSize, configuration: naturalConfiguration)
        let firstBranches = softMasks(in: firstFrame).filter {
            $0.role == .surfaceShadow && $0.shape == .capsule
        }
        let firstFoliage = softMasks(in: firstFrame).filter {
            $0.role == .surfaceShadow && $0.shape == .leaf
        }
        let laterFoliage = softMasks(in: laterFrame).filter {
            $0.role == .surfaceShadow && $0.shape == .leaf
        }
        let firstFlecks = softMasks(in: firstFrame).filter { $0.role == .surfaceHighlight }
        let laterFlecks = softMasks(in: laterFrame).filter { $0.role == .surfaceHighlight }
        XCTAssertEqual(firstBranches.count, 18)
        XCTAssertEqual(firstFoliage.count, 160)
        XCTAssertEqual(firstFlecks.count, 32)
        XCTAssertTrue(firstBranches.allSatisfy { $0.size.width < 6 })
        XCTAssertGreaterThan(firstFoliage.filter { $0.size.width / $0.size.height < 2.5 }.count, 150)
        let largestShimmer = zip(firstFoliage, laterFoliage).map {
            abs($0.opacity - $1.opacity)
        }.max() ?? 0
        XCTAssertGreaterThan(largestShimmer, 0.06)
        let largestFleckChange = zip(firstFlecks, laterFlecks).map {
            abs($0.opacity - $1.opacity)
        }.max() ?? 0
        XCTAssertGreaterThan(largestFleckChange, 0.05)
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
                XCTAssertLessThanOrEqual(frame.primitives.count, 216)
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
