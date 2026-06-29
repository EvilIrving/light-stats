//
//  UpdateService.swift
//  Light Stats
//
//  零依赖自研更新器的执行层（actor 隔离）：检查 GitHub 最新发布、下载 DMG、
//  三重安全校验（codesign 验签 + spctl 验公证 + 校验 Team ID），再把新 .app
//  暂存并写一个脱离进程的替换脚本——主进程退出后由脚本完成替换并重启。
//
//  设计红线：自动改写自身二进制，必须确认下载产物确由本团队签名+公证，
//  否则一律拒绝安装。
//

import Foundation
import os

actor UpdateService {

    /// 面向用户的公开仓库（About 与官网均指向此处）。
    static let repo = "EvilIrving/light-stats"
    /// 本团队的 Developer ID Team ID，校验下载产物归属。
    static let expectedTeamID = "QZZ878S3NS"

    private let logger = Logger(subsystem: "com.lightstats", category: "Update")

    enum UpdateError: LocalizedError {
        case network
        case noRelease
        case download
        case mountFailed
        case appNotFound
        case verificationFailed(String)

        var errorDescription: String? {
            switch self {
            case .network: return "update.error.network".localized
            case .noRelease: return "update.error.noRelease".localized
            case .download: return "update.error.download".localized
            case .mountFailed, .appNotFound: return "update.error.install".localized
            case .verificationFailed(let detail):
                return "update.error.verification".localized + " (\(detail))"
            }
        }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: - 检查最新版本

    /// `includePrereleases == true`：打 `/releases` 列表并接受 prerelease（手动「立即检查」
    /// 的内测通道）；否则打 `/releases/latest`，GitHub 天然只回稳定版（自动检查）。
    func fetchLatest(includePrereleases: Bool = false) async throws -> ReleaseInfo {
        let path = includePrereleases ? "releases?per_page=20" : "releases/latest"
        let endpoint = "https://api.github.com/repos/\(Self.repo)/\(path)"
        guard let url = URL(string: endpoint) else { throw UpdateError.network }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw UpdateError.noRelease
            }
            let release = includePrereleases
                ? ReleaseInfo.first(fromListJSON: data, allowPrerelease: true)
                : ReleaseInfo(json: data)
            guard let release else { throw UpdateError.noRelease }
            return release
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.network
        }
    }

    // MARK: - 下载（带进度，0...1）

    func download(_ release: ReleaseInfo, onProgress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightStatsUpdate-\(UUID().uuidString).dmg")
        do {
            let (stream, response) = try await session.bytes(from: release.downloadURL)
            let total = response.expectedContentLength
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }

            var buffer = Data()
            buffer.reserveCapacity(64 * 1024)
            var received: Int64 = 0
            for try await byte in stream {
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if total > 0 { onProgress(min(1.0, Double(received) / Double(total))) }
                }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
            onProgress(1.0)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw UpdateError.download
        }
    }

    // MARK: - 挂载 + 三重校验 + 暂存

    /// 挂载 DMG，定位 .app，做三重安全校验，把新 app ditto 到独立暂存目录后卸载 DMG。
    /// 返回暂存的 .app 路径，供 `installAndRelaunch` 使用。
    func verifyAndStage(dmgURL: URL) async throws -> URL {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightStatsMount-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let attach = run("/usr/bin/hdiutil", [
            "attach", dmgURL.path, "-nobrowse", "-noautoopen", "-readonly",
            "-mountpoint", mountPoint.path
        ])
        guard attach.status == 0 else { throw UpdateError.mountFailed }
        defer {
            _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
            try? FileManager.default.removeItem(at: dmgURL)
        }

        guard let mountedApp = locateApp(in: mountPoint) else { throw UpdateError.appNotFound }
        try verifySignature(of: mountedApp)

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightStatsStage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let staged = stagingDir.appendingPathComponent(mountedApp.lastPathComponent)
        let copy = run("/usr/bin/ditto", [mountedApp.path, staged.path])
        guard copy.status == 0 else { throw UpdateError.verificationFailed("ditto") }
        return staged
    }

    /// 三重校验：codesign 验签 + spctl 验公证（Gatekeeper）+ Team ID 必须匹配。
    private func verifySignature(of app: URL) throws {
        let verify = run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        guard verify.status == 0 else { throw UpdateError.verificationFailed("codesign") }

        let assess = run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=2", app.path])
        guard assess.status == 0 else { throw UpdateError.verificationFailed("notarization") }

        let display = run("/usr/bin/codesign", ["--display", "--verbose=4", app.path])
        let info = display.stderr + display.stdout
        guard info.contains("TeamIdentifier=\(Self.expectedTeamID)") else {
            throw UpdateError.verificationFailed("team-id")
        }
        logger.info("Update verified: signature + notarization + team id OK")
    }

    private func locateApp(in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.first { $0.pathExtension == "app" }
    }

    // MARK: - 替换并重启

    /// 写一个脱离进程的 shell 脚本：等当前进程退出 → ditto 覆盖 → 重启新版本。
    /// 调用后由调用方立即 `NSApp.terminate`，剩下交给脱离的脚本。
    func installAndRelaunch(stagedApp: URL, destination: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightStatsInstall-\(UUID().uuidString).sh")
        let script = """
        #!/bin/sh
        PID="$1"; SRC="$2"; DEST="$3"
        i=0
        while /bin/kill -0 "$PID" 2>/dev/null; do
          /bin/sleep 0.2; i=$((i+1)); [ $i -gt 150 ] && break
        done
        /bin/sleep 0.3
        if /usr/bin/ditto "$SRC" "$DEST.new"; then
          /bin/rm -rf "$DEST"
          /bin/mv "$DEST.new" "$DEST"
          /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
          /usr/bin/open "$DEST"
        fi
        /bin/rm -rf "$(/usr/bin/dirname "$SRC")"
        /bin/rm -f "$0"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [scriptURL.path, "\(pid)", stagedApp.path, destination.path]
        try task.run()
        logger.info("Installer launched; terminating to let it swap the bundle")
    }

    // MARK: - 进程小工具

    private func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do {
            try task.run()
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return (
                task.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? ""
            )
        } catch {
            return (-1, "", "\(error)")
        }
    }
}
