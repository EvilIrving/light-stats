//
//  PresentationPointerService.swift
//  Light Stats
//
//  Persistent presentation pointer: a click-through soft halo follows the
//  system cursor without installing an event tap or requesting permission.
//

import AppKit
import QuartzCore

@MainActor
protocol PresentationPointerControlling: AnyObject {
    var isRunning: Bool { get }
    func start()
    func stop()
}

/// Owns one small transparent window centered on `NSEvent.mouseLocation`.
/// Core Animation renders the pulse; Swift only repositions the window when
/// the cursor moves, so the steady-state effect avoids per-frame drawing.
@MainActor
final class PresentationPointerService: PresentationPointerControlling {
    private static let windowSize = CGSize(width: 112, height: 112)
    private static let trackingIntervalNanoseconds: UInt64 = 16_666_667

    private(set) var isRunning = false
    private var overlayWindow: NSWindow?
    private var trackingTask: Task<Void, Never>?
    private var lastPointerLocation: CGPoint?

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let window = makeOverlayWindow()
        overlayWindow = window
        updatePointerLocation()
        window.orderFrontRegardless()

        trackingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updatePointerLocation()
                try? await Task.sleep(nanoseconds: Self.trackingIntervalNanoseconds)
            }
        }
    }

    func stop() {
        guard isRunning || overlayWindow != nil else { return }
        isRunning = false
        trackingTask?.cancel()
        trackingTask = nil
        lastPointerLocation = nil
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    private func updatePointerLocation() {
        guard isRunning, let window = overlayWindow else { return }
        let pointer = NSEvent.mouseLocation
        if let lastPointerLocation,
           abs(pointer.x - lastPointerLocation.x) < 0.25,
           abs(pointer.y - lastPointerLocation.y) < 0.25 {
            return
        }
        lastPointerLocation = pointer
        window.setFrameOrigin(NSPoint(
            x: pointer.x - Self.windowSize.width / 2,
            y: pointer.y - Self.windowSize.height / 2
        ))
    }

    private func makeOverlayWindow() -> NSWindow {
        let frame = CGRect(origin: .zero, size: Self.windowSize)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = PresentationPointerHaloView(frame: frame)
        return window
    }
}

/// Fixed light body + dark keyline: the same halo remains legible over both
/// light and dark content without inspecting the application underneath it.
private final class PresentationPointerHaloView: NSView {
    private let haloContainer = CALayer()
    private let glowLayer = CAGradientLayer()
    private let darkRingLayer = CAShapeLayer()
    private let lightRingLayer = CAShapeLayer()
    private let darkAnchorLayer = CAShapeLayer()
    private let lightAnchorLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        configureLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PresentationPointerHaloView is created in code only")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateLayerGeometry()
        CATransaction.commit()
    }

    private func configureLayers() {
        guard let rootLayer = layer else { return }

        rootLayer.addSublayer(haloContainer)
        haloContainer.addSublayer(glowLayer)
        haloContainer.addSublayer(darkRingLayer)
        haloContainer.addSublayer(lightRingLayer)
        rootLayer.addSublayer(darkAnchorLayer)
        rootLayer.addSublayer(lightAnchorLayer)

        glowLayer.type = .radial
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        glowLayer.colors = [
            NSColor.clear.cgColor,
            NSColor(calibratedRed: 1, green: 0.83, blue: 0.32, alpha: 0.12).cgColor,
            NSColor(calibratedRed: 1, green: 0.62, blue: 0.12, alpha: 0.25).cgColor,
            NSColor(calibratedRed: 1, green: 0.56, blue: 0.08, alpha: 0).cgColor
        ]
        glowLayer.locations = [0, 0.28, 0.62, 1]

        configureRing(
            darkRingLayer,
            color: NSColor(calibratedWhite: 0.02, alpha: 0.82),
            width: 4
        )
        configureRing(
            lightRingLayer,
            color: NSColor(calibratedRed: 1, green: 0.96, blue: 0.77, alpha: 0.96),
            width: 1.35
        )
        lightRingLayer.shadowColor = NSColor(calibratedRed: 1, green: 0.55, blue: 0.08, alpha: 0.9).cgColor
        lightRingLayer.shadowOpacity = 1
        lightRingLayer.shadowRadius = 8
        lightRingLayer.shadowOffset = .zero

        configureRing(darkAnchorLayer, color: NSColor(calibratedWhite: 0.02, alpha: 0.94), width: 4)
        configureRing(lightAnchorLayer, color: NSColor(calibratedWhite: 1, alpha: 0.98), width: 1.25)

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.97
        pulse.toValue = 1.04
        pulse.duration = 1.35
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        haloContainer.add(pulse, forKey: "presentationPointerPulse")
    }

    private func configureRing(_ layer: CAShapeLayer, color: NSColor, width: CGFloat) {
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = color.cgColor
        layer.lineWidth = width
    }

    private func updateLayerGeometry() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        haloContainer.frame = bounds
        haloContainer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        haloContainer.position = center
        glowLayer.frame = bounds.insetBy(dx: 9, dy: 9)

        let ringRect = CGRect(
            x: center.x - 27,
            y: center.y - 27,
            width: 54,
            height: 54
        )
        let ringPath = CGPath(ellipseIn: ringRect, transform: nil)
        darkRingLayer.frame = bounds
        darkRingLayer.path = ringPath
        lightRingLayer.frame = bounds
        lightRingLayer.path = ringPath

        let anchorRect = CGRect(
            x: center.x - 5.2,
            y: center.y - 5.2,
            width: 10.4,
            height: 10.4
        )
        let anchorPath = CGPath(ellipseIn: anchorRect, transform: nil)
        darkAnchorLayer.frame = bounds
        darkAnchorLayer.path = anchorPath
        lightAnchorLayer.frame = bounds
        lightAnchorLayer.path = anchorPath
    }
}
