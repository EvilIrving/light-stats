nonisolated struct ProcessMemorySummary: Sendable {
    let knownBytes: UInt64
    let unavailableCount: Int

    init(_ footprints: [UInt64?]) {
        unavailableCount = footprints.filter { $0 == nil }.count
        knownBytes = footprints.compactMap { $0 }.reduce(UInt64(0)) { total, bytes in
            let sum = total.addingReportingOverflow(bytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
    }
}
