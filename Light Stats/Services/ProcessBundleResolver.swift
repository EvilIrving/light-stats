import Foundation

nonisolated enum ProcessBundleResolver {
    /// Embedded renderers and app extensions count toward their outer application.
    static func rootBundlePath(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.upperBound].dropLast())
    }

    static func resolve(_ path: String) -> ProcessBundleInfo {
        guard let root = rootBundlePath(in: path) else {
            return ProcessBundleInfo(execPath: path, bundlePath: nil, bundleId: nil)
        }
        return ProcessBundleInfo(execPath: path, bundlePath: root, bundleId: Bundle(path: root)?.bundleIdentifier)
    }
}
