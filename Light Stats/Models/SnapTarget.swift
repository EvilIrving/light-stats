//
//  SnapTarget.swift
//  Light Stats
//

import Foundation

/// What a snap request wants the window to become.
///
/// Two shapes only. Everything the engine can do is either one of the fixed actions the menu bar
/// and the default shortcuts expose, or a normalized region produced by the layout catalog, the
/// grid selector, or the drag-zone detector. Normalizing at this boundary is what lets the preview
/// overlay and the placement engine share one geometry path, so the preview cannot show one
/// footprint in one place and drop the window in another.
enum SnapTarget: Hashable, Sendable {
    case action(WindowSnapAction)
    case region(SnapNormalizedRect)
    /// Hiding applications rather than moving windows. The third kind of thing a recorded shortcut
    /// can do, and the reason `SnapTarget` is not simply "a rectangle".
    case visibility(WindowVisibilityCommand)

    /// Stable label for diagnostics.
    var diagnosticName: String {
        switch self {
        case .action(let action): return action.rawValue
        case .region(let rect):
            return String(format: "region(%.3f,%.3f,%.3f,%.3f)", rect.x, rect.y, rect.width, rect.height)
        case .visibility(let command): return "visibility.\(command.rawValue)"
        }
    }

    /// Whether this target needs Accessibility to act. Hiding and restoring applications is
    /// `NSRunningApplication`'s own API and needs no permission at all.
    var requiresAccessibility: Bool {
        if case .visibility = self { return false }
        return true
    }

    /// The action this target stands for, when it is one.
    var action: WindowSnapAction? {
        guard case .action(let action) = self else { return nil }
        return action
    }

    /// The region this target stands for, when it is one.
    var region: SnapNormalizedRect? {
        guard case .region(let rect) = self else { return nil }
        return rect
    }
}

// Explicit coding rather than compiler synthesis: the synthesized shape for an enum with
// associated values is positional (`"_0"`), and these values are persisted in the user's
// shortcuts. A positional encoding would silently change meaning the first time a case moves.
extension SnapTarget: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind
        case action
        case command
        case x, y, width, height
    }

    private enum Kind: String, Codable {
        case action
        case region
        case visibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .action:
            self = .action(try container.decode(WindowSnapAction.self, forKey: .action))
        case .region:
            self = .region(
                SnapNormalizedRect(
                    x: try container.decode(Double.self, forKey: .x),
                    y: try container.decode(Double.self, forKey: .y),
                    width: try container.decode(Double.self, forKey: .width),
                    height: try container.decode(Double.self, forKey: .height)
                )
            )
        case .visibility:
            self = .visibility(try container.decode(WindowVisibilityCommand.self, forKey: .command))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let action):
            try container.encode(Kind.action, forKey: .kind)
            try container.encode(action, forKey: .action)
        case .region(let rect):
            try container.encode(Kind.region, forKey: .kind)
            try container.encode(rect.x, forKey: .x)
            try container.encode(rect.y, forKey: .y)
            try container.encode(rect.width, forKey: .width)
            try container.encode(rect.height, forKey: .height)
        case .visibility(let command):
            try container.encode(Kind.visibility, forKey: .kind)
            try container.encode(command, forKey: .command)
        }
    }
}
