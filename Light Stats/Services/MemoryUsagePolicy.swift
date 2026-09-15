/// Anonymous pages can be inactive while still belonging to applications.
/// File-backed caches are reclaimable and are not application memory. Purgeable
/// anonymous pages are excluded; compressed is the compressor's physical storage,
/// not the uncompressed size of its contents. These counters may change mid-read.
nonisolated enum MemoryUsagePolicy {
    static func usedBytes(
        total: UInt64,
        anonymous: UInt64,
        purgeable: UInt64,
        wired: UInt64,
        compressed: UInt64
    ) -> UInt64 {
        let app = anonymous - min(anonymous, purgeable)
        return [app, wired, compressed].reduce(UInt64(0)) { sum, bytes in
            sum + min(bytes, total - sum)
        }
    }
}
