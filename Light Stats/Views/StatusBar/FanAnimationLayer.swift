//
//  FanAnimationLayer.swift
//  Light Stats
//
//  Core Animation-backed status-bar fan. The icon is rendered once as an alpha
//  mask; rotation and RPM changes stay on the compositing side.
//

import AppKit
import QuartzCore

final class FanAnimationLayer: CALayer {

    // MARK: - Constants

    static let maxRevPerSecond: Double = 3
    static let rpmAtMaxSpeed: Double = 5_000

    private static let iconName = "fanblades.fill"
    private static let iconPointSize: CGFloat = 14
    private static let rotationAnimationKey = "status-bar-fan-rotation"

    // MARK: - Layers

    private var iconLayer = CALayer()
    private var iconMask: CALayer?
    private var iconMaskScale: CGFloat?

    // MARK: - State

    /// Rotation animation progress, in one duration cycle (0...1).
    private var phase: Double = 0
    private var currentSpeed: Double = 0

    // MARK: - Initialization

    override init() {
        super.init()
        configure()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        guard let source = layer as? FanAnimationLayer else { return }
        phase = source.phase
        currentSpeed = source.currentSpeed
        iconMaskScale = source.iconMaskScale
        if let copiedIconLayer = sublayers?.first {
            iconLayer = copiedIconLayer
            iconMask = copiedIconLayer.mask
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        iconLayer.removeAllAnimations()
    }

    // MARK: - Public Methods

    func update(rpm: Int?, visible: Bool, contentsScale: CGFloat, tintColor: NSColor) {
        self.contentsScale = contentsScale
        iconLayer.contentsScale = contentsScale
        iconLayer.backgroundColor = tintColor.cgColor

        guard visible else {
            stop()
            return
        }

        isHidden = false
        ensureRotationAnimation()
        ensureIconMask(contentsScale: contentsScale)
        setSpeed(Self.visualSpeed(for: rpm))
    }

    func updateTint(_ tintColor: NSColor) {
        iconLayer.backgroundColor = tintColor.cgColor
    }

    func stop() {
        phase = currentPhase(at: CACurrentMediaTime())
        currentSpeed = 0
        iconLayer.removeAnimation(forKey: Self.rotationAnimationKey)
        iconLayer.speed = 0
        iconLayer.timeOffset = phase
        iconLayer.beginTime = 0
        isHidden = true
    }

    static func visualSpeed(for rpm: Int?) -> Double {
        guard let rpm, rpm > 0 else { return 0 }
        return min(Double(rpm) / rpmAtMaxSpeed, 1) * maxRevPerSecond
    }

    // MARK: - CALayer Layout

    override func layoutSublayers() {
        super.layoutSublayers()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let iconSize = min(Self.iconPointSize, min(bounds.width, bounds.height))
        iconLayer.frame = CGRect(
            x: bounds.midX - iconSize / 2,
            y: bounds.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        iconMask?.frame = iconLayer.bounds
        CATransaction.commit()
    }

    // MARK: - Private Methods

    private func configure() {
        masksToBounds = false
        iconLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.masksToBounds = false
        addSublayer(iconLayer)
        ensureRotationAnimation()
        iconLayer.speed = 0
    }

    private func ensureRotationAnimation() {
        guard iconLayer.animation(forKey: Self.rotationAnimationKey) == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = -Double.pi * 2
        animation.duration = 1
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        iconLayer.add(animation, forKey: Self.rotationAnimationKey)
        iconLayer.speed = 0
        iconLayer.timeOffset = phase
    }

    private func setSpeed(_ speed: Double) {
        let nextSpeed = max(speed, 0)
        guard abs(nextSpeed - currentSpeed) > 0.0001 else { return }

        let now = CACurrentMediaTime()
        phase = currentPhase(at: now)
        currentSpeed = nextSpeed

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.speed = 0
        iconLayer.timeOffset = phase
        iconLayer.beginTime = 0
        if currentSpeed > 0 {
            let parentTime = convertTime(now, from: nil)
            iconLayer.beginTime = parentTime
            iconLayer.speed = Float(currentSpeed)
        }
        CATransaction.commit()
    }

    private func currentPhase(at time: CFTimeInterval) -> Double {
        guard currentSpeed > 0 else { return phase }
        let layerTime = iconLayer.convertTime(time, from: nil)
        return normalizedPhase(layerTime)
    }

    private func ensureIconMask(contentsScale: CGFloat) {
        guard iconMaskScale != contentsScale else { return }
        guard let maskImage = Self.makeMaskImage(scale: contentsScale) else { return }

        let mask = iconMask ?? CALayer()
        mask.contents = maskImage
        mask.contentsScale = contentsScale
        mask.contentsGravity = .resizeAspect
        mask.frame = iconLayer.bounds
        iconLayer.mask = mask
        iconMask = mask
        iconMaskScale = contentsScale
        setNeedsLayout()
    }

    private static func makeMaskImage(scale: CGFloat) -> CGImage? {
        guard let symbol = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: "Fan"
        ) else { return nil }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: iconPointSize,
            weight: .regular
        )
        let configuredSymbol = symbol.withSymbolConfiguration(configuration) ?? symbol
        let pixelSize = max(Int((iconPointSize * scale).rounded(.up)), 1)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        graphicsContext.cgContext.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.cgContext.saveGState()
        graphicsContext.cgContext.scaleBy(x: scale, y: scale)
        configuredSymbol.draw(
            in: NSRect(x: 0, y: 0, width: iconPointSize, height: iconPointSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: nil
        )
        graphicsContext.cgContext.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }

    private func normalizedPhase(_ value: Double) -> Double {
        let cycle = 1.0
        let remainder = value.truncatingRemainder(dividingBy: cycle)
        return remainder >= 0 ? remainder : remainder + cycle
    }
}
