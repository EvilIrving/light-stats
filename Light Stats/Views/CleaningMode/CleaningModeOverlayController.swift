//
//  CleaningModeOverlayController.swift
//  Light Stats
//
//  清洁模式遮罩窗口管理：为每个 NSScreen 建一个全屏无边框遮罩窗口，
//  随 CleaningModeViewModel.isActive 显示/关闭；显示期间监听屏幕变化
//  （插拔外接显示器）重建窗口集合。
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class CleaningModeOverlayController {

    static let shared = CleaningModeOverlayController()

    private let viewModel: CleaningModeViewModel
    private var windows: [NSWindow] = []
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: CleaningModeViewModel = .shared) {
        self.viewModel = viewModel
        observe()
    }

    private func observe() {
        viewModel.$isActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                isActive ? self?.showOverlays() : self?.hideOverlays()
            }
            .store(in: &cancellables)
    }

    private func showOverlays() {
        rebuildWindows()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func hideOverlays() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    @objc private func handleScreenChange() {
        guard viewModel.isActive else { return }
        rebuildWindows()
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map(makeWindow)
        windows.forEach { $0.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: CleaningModeOverlayView(viewModel: viewModel)
        )
        window.setFrame(screen.frame, display: true)
        return window
    }
}
