//
//  MetricTrendStoreTests.swift
//  LightStatsTests
//

import XCTest
@testable import Light_Stats

final class MetricTrendStoreTests: XCTestCase {

    func testSaveReplacesSameMillisecondTimestampAfterPersistence() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("metric-trends.json")
        let timestamp = Date(timeIntervalSince1970: 1_788_486_169.859_114)
        let referenceDate = timestamp.addingTimeInterval(1)
        let store = MetricTrendStore(fileURL: fileURL)

        await store.save(sample(timestamp: timestamp, cpu: 10), referenceDate: referenceDate)
        await store.save(
            sample(timestamp: timestamp.addingTimeInterval(0.000_000_1), cpu: 80),
            referenceDate: referenceDate
        )

        let restartedStore = MetricTrendStore(fileURL: fileURL)
        let restored = await restartedStore.load(referenceDate: referenceDate)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.cpu, 80)
    }

    func testLoadCollapsesLegacyDuplicateTimestamps() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("metric-trends.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let timestamp = Date(timeIntervalSince1970: 1_788_486_169.859_114)
        let samples = [
            sample(timestamp: timestamp, cpu: 10),
            sample(timestamp: timestamp.addingTimeInterval(0.000_000_1), cpu: 20),
            sample(timestamp: timestamp.addingTimeInterval(MetricTrendStore.sampleInterval), cpu: 30)
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(samples).write(to: fileURL)

        let store = MetricTrendStore(fileURL: fileURL)
        let restored = await store.load(referenceDate: timestamp.addingTimeInterval(60))

        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.map(\.cpu), [20, 30])
    }

    private func sample(timestamp: Date, cpu: Double) -> MetricTrendSample {
        MetricTrendSample(
            timestamp: timestamp,
            cpu: cpu,
            memory: 50,
            gpu: 25,
            load: 20,
            networkUp: 100,
            networkDown: 200
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
