//
//  MetricTrendStore.swift
//  Light Stats
//

import Foundation

/// 将最近三小时趋势保存到本地。完整历史只在读写文件时短暂进入内存，
/// 常驻内存由 `SystemMonitor` 的小型绘图缓冲负责。
actor MetricTrendStore {
    nonisolated static let retention: TimeInterval = 3 * 60 * 60
    nonisolated static let sampleInterval: TimeInterval = 45
    nonisolated static let provisionalWriteInterval: TimeInterval = 10
    nonisolated static let maximumSampleCount = Int(retention / sampleInterval)

    private static let logger = AppLogger(category: "MetricTrendStore")
    private static let timestampTolerance: TimeInterval = 0.001

    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        fileURL = applicationSupport
            .appendingPathComponent("Light Stats/History", isDirectory: true)
            .appendingPathComponent("metric-trends-v1.json")
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func load(referenceDate: Date = Date()) -> [MetricTrendSample] {
        do {
            return retained(try readSamples(), referenceDate: referenceDate)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch {
            Self.logger.error("Metric trend history read failed: \(error.localizedDescription)")
            return []
        }
    }

    func save(_ sample: MetricTrendSample, referenceDate: Date = Date()) {
        var samples: [MetricTrendSample]
        do {
            samples = try readSamples()
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            samples = []
        } catch {
            Self.logger.error("Metric trend history recovery failed: \(error.localizedDescription)")
            samples = []
        }

        samples.removeAll { isSameTimestamp($0.timestamp, sample.timestamp) }
        samples.append(sample)
        samples = retained(samples, referenceDate: referenceDate)

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            try encoder.encode(samples).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Self.logger.error("Metric trend history write failed: \(error.localizedDescription)")
        }
    }

    private func readSamples() throws -> [MetricTrendSample] {
        try decoder.decode([MetricTrendSample].self, from: Data(contentsOf: fileURL))
    }

    private func retained(_ samples: [MetricTrendSample], referenceDate: Date) -> [MetricTrendSample] {
        let cutoff = referenceDate.addingTimeInterval(-Self.retention)
        var uniqueSamples: [MetricTrendSample] = []
        for sample in samples where sample.timestamp >= cutoff && sample.timestamp <= referenceDate {
            if let index = uniqueSamples.firstIndex(where: {
                isSameTimestamp($0.timestamp, sample.timestamp)
            }) {
                uniqueSamples[index] = sample
            } else {
                uniqueSamples.append(sample)
            }
        }
        let recent = uniqueSamples.sorted { $0.timestamp < $1.timestamp }
        return Array(recent.suffix(Self.maximumSampleCount))
    }

    /// JSON 日期往返可能引入亚微秒浮点误差；相差不足一毫秒视为同一个趋势桶。
    private func isSameTimestamp(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < Self.timestampTolerance
    }
}
