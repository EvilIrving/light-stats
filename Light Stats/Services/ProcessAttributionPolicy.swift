import Foundation

nonisolated enum ProcessAttributionPolicy {
    static func resolveGroup(
        for process: TopProcessInfo,
        responsiblePid: pid_t,
        processBundleInfo: ProcessBundleInfo,
        responsibleBundleInfo: ProcessBundleInfo?,
        monitoredByPid: [pid_t: String],
        monitoredByBundleId: [String: String],
        monitoredByBundlePath: [String: String],
        parentByPid: [pid_t: pid_t]
    ) -> ProcessGroupResolution? {
        // A separately running GUI app keeps its own group even when launched by
        // Terminal. Embedded helpers already map to their canonical outer bundle.
        if let key = monitoredByPid[process.pid] {
            return ProcessGroupResolution(groupKey: key, source: .owningApp)
        }
        if responsiblePid > 0, let key = monitoredByPid[responsiblePid] {
            return ProcessGroupResolution(groupKey: key, source: .responsibility)
        }
        if let bundleId = responsibleBundleInfo?.bundleId {
            if let key = monitoredByBundleId[bundleId] {
                return ProcessGroupResolution(groupKey: key, source: .responsibility)
            }
            if let key = inferredParentBundleGroupKey(
                for: bundleId,
                monitoredByBundleId: monitoredByBundleId
            ) {
                return ProcessGroupResolution(groupKey: key, source: .responsibility)
            }
        }
        if let bundleId = processBundleInfo.bundleId {
            if let key = monitoredByBundleId[bundleId] {
                return ProcessGroupResolution(groupKey: key, source: .bundle)
            }
            if let key = inferredParentBundleGroupKey(
                for: bundleId,
                monitoredByBundleId: monitoredByBundleId
            ) {
                return ProcessGroupResolution(groupKey: key, source: .bundle)
            }
        }
        if let bundlePath = responsibleBundleInfo?.bundlePath, let key = monitoredByBundlePath[bundlePath] {
            return ProcessGroupResolution(groupKey: key, source: .responsibility)
        }
        if let bundlePath = processBundleInfo.bundlePath, let key = monitoredByBundlePath[bundlePath] {
            return ProcessGroupResolution(groupKey: key, source: .bundle)
        }
        if let key = resolveGroupKeyFromParentChain(
            for: process,
            parentByPid: parentByPid,
            monitoredByPid: monitoredByPid
        ) {
            return ProcessGroupResolution(groupKey: key, source: .parentProcess)
        }
        return nil
    }

    private static func resolveGroupKeyFromParentChain(
        for process: TopProcessInfo,
        parentByPid: [pid_t: pid_t],
        monitoredByPid: [pid_t: String]
    ) -> String? {
        var visited = Set<pid_t>()
        var parentPid = process.parentPid
        var depth = 0

        while parentPid > 1 && depth < 32 {
            if let key = monitoredByPid[parentPid] {
                return key
            }
            guard visited.insert(parentPid).inserted else { return nil }
            guard let nextParentPid = parentByPid[parentPid] else { return nil }
            parentPid = nextParentPid
            depth += 1
        }
        return nil
    }

    private static func inferredParentBundleGroupKey(
        for bundleId: String,
        monitoredByBundleId: [String: String]
    ) -> String? {
        let components = bundleId
            .split(separator: ".")
            .map(String.init)
        guard components.count > 1 else { return nil }

        guard let lastComponent = components.last else { return nil }
        let lowerLast = lastComponent.lowercased()
        let helperMarkers = ["helper", "renderer", "gpu", "plugin", "utility", "extension", "xpc", "appex"]
        guard helperMarkers.contains(where: { lowerLast.contains($0) }) else { return nil }

        var parentComponents = components
        while parentComponents.count > 1 {
            parentComponents.removeLast()
            let parentBundleId = parentComponents.joined(separator: ".")
            if let key = monitoredByBundleId[parentBundleId] {
                return key
            }
        }
        return nil
    }
}
