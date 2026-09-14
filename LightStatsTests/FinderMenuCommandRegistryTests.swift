//
//  FinderMenuCommandRegistryTests.swift
//  LightStatsTests
//
//  锁住「右键菜单点了没反应」那条回归。
//
//  FinderSync 会把扩展返回的 NSMenu 编组后交给 Finder 显示，点击再回调扩展；跨这一趟
//  **只有 `NSMenuItem.tag` 能活着回来，`representedObject` 会变成 nil**。1.9.3 改成
//  representedObject 之后，`runAction` 的 guard 直接 return，整份菜单的点击都无声消失。
//
//  纯数据结构，不碰 Finder、不建窗口，所以是普通单元测试。
//

import XCTest
@testable import Light_Stats

final class FinderMenuCommandRegistryTests: XCTestCase {

    private func sampleCommand(parameter: String = "blank-docx") -> FinderMenuCommand {
        FinderMenuCommand(.newFile, parameter: parameter, paths: ["/Users/me/a.txt"], container: "/Users/me")
    }

    func testRegisteredTagResolvesBackToTheSameCommand() throws {
        let registry = FinderMenuCommandRegistry()
        let original = FinderMenuCommand(
            .moveTo, parameter: "/Users/me/Desktop", paths: ["/Users/me/a.txt"], container: "/Users/me"
        )

        let tag = registry.register(original)
        let resolved = try XCTUnwrap(registry.command(for: tag))

        XCTAssertEqual(resolved.action, .moveTo)
        XCTAssertEqual(resolved.parameter, "/Users/me/Desktop")
        XCTAssertEqual(resolved.paths, ["/Users/me/a.txt"])
        XCTAssertEqual(resolved.container, "/Users/me")
    }

    func testTagsAreUniqueAndMonotonic() {
        let registry = FinderMenuCommandRegistry()
        let tags = (0..<50).map { _ in registry.register(sampleCommand()) }
        XCTAssertEqual(tags, Array(1...50))
    }

    /// Finder 完全可能在旧菜单还开着的时候重建一次菜单（右键空白处、切目录、挂载卷）。
    /// 重建之前发出去的 tag 必须仍然查得到——1.9.2 每次 menu(for:) 清空表，这里就断了。
    func testRebuildingTheMenuKeepsEarlierTagsResolvable() throws {
        let registry = FinderMenuCommandRegistry()
        let first = registry.register(FinderMenuCommand(.copyPath, container: "/tmp"))
        let second = registry.register(FinderMenuCommand(.openTerminalHere, container: "/tmp"))

        for _ in 0..<40 { _ = registry.register(sampleCommand()) }

        XCTAssertEqual(try XCTUnwrap(registry.command(for: first)).action, .copyPath)
        XCTAssertEqual(try XCTUnwrap(registry.command(for: second)).action, .openTerminalHere)
    }

    /// 认不出的 tag 返回 nil 是契约：调用方必须显式处理，不能静默吞掉点击。
    /// tag 0 是 NSMenuItem 的默认值，也就是「不是本扩展建的项」。
    func testUnknownTagResolvesToNil() {
        let registry = FinderMenuCommandRegistry()
        _ = registry.register(sampleCommand())
        XCTAssertNil(registry.command(for: 0))
        XCTAssertNil(registry.command(for: 9_999))
    }

    func testCapacityEvictsOldestAndKeepsNewest() throws {
        let registry = FinderMenuCommandRegistry(capacity: 3)
        let tags = (0..<5).map { index in
            registry.register(FinderMenuCommand(.newFile, parameter: "t\(index)", container: "/tmp"))
        }

        XCTAssertEqual(registry.count, 3)
        XCTAssertNil(registry.command(for: tags[0]))
        XCTAssertNil(registry.command(for: tags[1]))
        for tag in tags[2...] {
            XCTAssertNotNil(registry.command(for: tag))
        }
        XCTAssertEqual(try XCTUnwrap(registry.command(for: tags[4])).parameter, "t4")
    }

    func testCapacityIsClampedToAtLeastOne() {
        let registry = FinderMenuCommandRegistry(capacity: 0)
        let tag = registry.register(sampleCommand())
        XCTAssertEqual(registry.count, 1)
        XCTAssertNotNil(registry.command(for: tag))
    }
}
