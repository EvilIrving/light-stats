//
//  SVGIcon.swift
//  Light Stats
//
//  Bundle SVG → template-tinted SwiftUI image. Used for monochrome metric
//  SVG assets under Resources/Icons/.
//

import AppKit
import SwiftUI

/// Well-known monochrome SVG resources in `Resources/Icons/`.
enum AppSVGIcon: String {
    case cpu
    case gpu
    case memory
    case network
    case proxy
    case disk
    case temperature
    case processes
    case batteryCharge = "battery-charge"
}

/// Renders a bundle SVG as a template image (picks up `foregroundStyle` / tint).
struct SVGIcon: View {
    let name: String
    var size: CGFloat = 12

    init(_ icon: AppSVGIcon, size: CGFloat = 12) {
        self.name = icon.rawValue
        self.size = size
    }

    init(name: String, size: CGFloat = 12) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Group {
            if let image = SVGIconLoader.shared.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Loads and caches SVG files from the app bundle as template `NSImage`s.
final class SVGIconLoader: @unchecked Sendable {
    static let shared = SVGIconLoader()

    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]

    private init() {}

    func image(named name: String) -> NSImage? {
        lock.lock()
        if let cached = cache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let url = Self.resolveURL(named: name),
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            return nil
        }
        image.isTemplate = true
        // Prefer a high-res bitmap cache so small UI sizes stay sharp.
        image.size = NSSize(width: 24, height: 24)

        lock.lock()
        cache[name] = image
        lock.unlock()
        return image
    }

    private static func resolveURL(named name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Icons") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Resources/Icons") {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: "svg")
    }
}
