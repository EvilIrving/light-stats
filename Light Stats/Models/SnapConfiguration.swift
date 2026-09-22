//
//  SnapConfiguration.swift
//  Light Stats
//

import Foundation

/// Everything the window-snap subsystem needs to know about the user's choices.
///
/// One value, one `UserDefaults` key, one JSON blob. The alternative — a dozen `@Published` Bools
/// with a dozen `Key` cases — spreads a single feature across a settings facade that is already the
/// largest file in the project, and turns "reset window management" into a twelve-step operation.
struct SnapConfiguration: Hashable, Sendable {

    /// Which implementation owns drag-to-edge: Light Stats' engine, or macOS itself.
    ///
    /// Replaced the old pair of raw system-preference toggles. Two independently switchable
    /// implementations of one gesture could both be live, which is not a state a user can reason
    /// about — see `SnapEdgeOwner`.
    var edgeOwner: SnapEdgeOwner
    var zones: SnapZoneConfiguration
    var island: SnapIslandConfiguration
    /// Show the translucent footprint overlay while a drag is armed.
    ///
    /// Not a settings toggle — always on for product builds after `withProductFixedPreferences()`.
    var showsPreview: Bool
    /// Honour the built-in list of apps whose windows must not be touched.
    var honorsRestrictedApps: Bool
    /// Bundle identifiers the user excluded by hand.
    var exclusions: [String]
    /// Global shortcuts. Empty means the user deleted them all, which is a valid choice.
    var shortcuts: [SnapShortcut]
    /// Layouts the user built with the grid selector.
    var customLayouts: [SnapLayout]
    /// Regions the user kept from the grid selector.
    var savedPlacements: [SnapSavedPlacement]
    /// Shaking a window sideways while dragging hides every other application.
    var isShakeToHideEnabled: Bool
    /// Layout ids shown in the island, in order. Built-in ids and custom ids share one list.
    var islandLayoutIDs: [String]
    /// Tile palette for the island.
    ///
    /// Not a settings control — fixed to `.neutral` after `withProductFixedPreferences()`.
    var islandPalette: SnapIslandMetrics.Palette
    /// Show hover previews above the Dock.
    var isDockPreviewEnabled: Bool
    /// Replace the system application switcher with a window-level one.
    var isCommandTabPlusEnabled: Bool
    /// Capture window pictures. **This is the switch that needs Screen Recording.** Off means the
    /// preview surfaces still work, showing titles and icons instead of images.
    var isWindowThumbnailsEnabled: Bool
    /// Clicking a running app's Dock icon puts its windows away, and clicking again brings them back.
    ///
    /// On by default: the only click it changes is the one macOS leaves doing nothing (the frontmost
    /// app's own icon), it needs no permission beyond Accessibility, and every effect is reversible
    /// with the same gesture.
    var isDockClickCollapseEnabled: Bool

    static let `default` = SnapConfiguration(
        edgeOwner: .lightStats,
        zones: .default,
        island: .default,
        showsPreview: true,
        honorsRestrictedApps: true,
        exclusions: [],
        shortcuts: defaultShortcuts,
        customLayouts: [],
        savedPlacements: [],
        isShakeToHideEnabled: true,
        islandLayoutIDs: defaultIslandLayoutIDs,
        islandPalette: .neutral,
        isDockPreviewEnabled: true,
        isCommandTabPlusEnabled: true,
        isWindowThumbnailsEnabled: false,
        isDockClickCollapseEnabled: true
    )

    static let defaultIslandLayoutIDs: [String] = [
        SnapLayoutCatalog.halvesID,
        SnapLayoutCatalog.thirdsID,
        SnapLayoutCatalog.quadrantsID,
        SnapLayoutCatalog.rightStackID
    ]

    /// Control + Option, the modifier pair the previous fixed set used.
    static let defaultModifiers: UInt32 = WindowSnapKeyCode.control | WindowSnapKeyCode.option

    /// The shortcut set every install starts with — the six bindings the hardcoded set used, now
    /// editable and extensible.
    static let defaultShortcuts: [SnapShortcut] = [
        SnapShortcut(action: .leftHalf, keyCode: WindowSnapKeyCode.leftArrow, modifiers: defaultModifiers),
        SnapShortcut(action: .rightHalf, keyCode: WindowSnapKeyCode.rightArrow, modifiers: defaultModifiers),
        SnapShortcut(action: .topHalf, keyCode: WindowSnapKeyCode.upArrow, modifiers: defaultModifiers),
        SnapShortcut(action: .bottomHalf, keyCode: WindowSnapKeyCode.downArrow, modifiers: defaultModifiers),
        SnapShortcut(action: .maximize, keyCode: WindowSnapKeyCode.return, modifiers: defaultModifiers),
        SnapShortcut(action: .center, keyCode: WindowSnapKeyCode.c, modifiers: defaultModifiers)
    ]

    // MARK: - Derived

    /// Layouts in `islandLayoutIDs` order, resolved against the catalog and the user's own layouts.
    var islandLayouts: [SnapLayout] {
        islandLayoutIDs.compactMap { layout(id: $0) }
    }

    /// Every layout the user can choose, built-ins first.
    var allLayouts: [SnapLayout] {
        SnapLayoutCatalog.builtIn + customLayouts
    }

    var exclusionSet: Set<String> { Set(exclusions) }

    /// Whether the drag monitor has anything to do at all.
    ///
    /// Reads the *effective* zones, so with macOS owning the gesture this is true only while
    /// shake-to-hide still needs the monitor.
    var isDragSnappingActive: Bool { effectiveZones.isActive || isShakeToHideEnabled }

    /// The zone rules as the drag pipeline should actually apply them.
    ///
    /// With macOS owning the gesture the zones are inert: the system tiles the window itself, so
    /// arming a zone here would put a second implementation back on the same mouse-up. The monitor
    /// still runs — shake-to-hide is a different gesture and shares the same pipeline.
    ///
    /// The island can only open if it has something to show. With the user's layouts all deleted,
    /// "island" would otherwise consume the top edge and produce no preview and no placement — a
    /// gesture that visibly does nothing. Falling back to filling the screen keeps the top edge
    /// useful instead of silently dead.
    var effectiveZones: SnapZoneConfiguration {
        guard edgeOwner == .lightStats else { return .disabled }
        var adjusted = zones
        adjusted.edgeThreshold = max(adjusted.edgeThreshold, 24)
        if zones.topEdgeMode == .island, islandLayouts.isEmpty { adjusted.topEdgeMode = .maximize }
        return adjusted
    }

    /// Whether a placement goes through macOS' own Window-menu tiling command.
    ///
    /// Not a preference of its own: choosing macOS as the owner *is* the statement that the system's
    /// implementation should do the work. A drag resolves to a `.region` target and the system has no
    /// command for a rectangle, so the old "let macOS place the window" switch could never affect the
    /// gesture users actually reach for — it only ever governed shortcut- and menu-driven snaps,
    /// which do carry an action.
    var prefersNativeTiling: Bool { edgeOwner == .system }

    func layout(id: String) -> SnapLayout? {
        SnapLayoutCatalog.layout(id: id) ?? customLayouts.first { $0.id == id }
    }

    /// The shortcut bound to a target, or an unbound placeholder so the settings list can show one
    /// row per action without having to special-case the missing ones.
    func shortcut(for target: SnapTarget) -> SnapShortcut {
        shortcuts.first { $0.target == target }
            ?? SnapShortcut(target: target, keyCode: 0, modifiers: 0)
    }

    /// Replaces a shortcut for the same target, or appends it. One binding per target is what makes
    /// the settings list behave like a list rather than a bag of duplicates.
    mutating func setShortcut(_ shortcut: SnapShortcut) {
        if shortcut.isBound {
            shortcuts.removeAll {
                $0.target != shortcut.target && $0.keyCode == shortcut.keyCode && $0.modifiers == shortcut.modifiers
            }
        }
        if let index = shortcuts.firstIndex(where: { $0.target == shortcut.target }) {
            shortcuts[index] = shortcut
        } else {
            shortcuts.append(shortcut)
        }
    }

    mutating func removeShortcut(for target: SnapTarget) {
        shortcuts.removeAll { $0.target == target }
    }

    /// Deletes bindings and island tiles that no longer resolve, so removing a layout cannot leave
    /// the island pointing at a hole.
    mutating func pruneDanglingReferences() {
        let knownLayoutIDs = Set(allLayouts.map(\.id))
        let hadPinnedLayouts = !islandLayoutIDs.isEmpty
        var seen = Set<String>()
        islandLayoutIDs = islandLayoutIDs.filter { knownLayoutIDs.contains($0) && seen.insert($0).inserted }
        if hadPinnedLayouts, islandLayoutIDs.isEmpty {
            islandLayoutIDs = Self.defaultIslandLayoutIDs.filter { knownLayoutIDs.contains($0) }
        }

        let knownRegions = Set(allLayouts.flatMap { $0.segments.map(\.rect) })
            .union(savedPlacements.map(\.rect))
        shortcuts.removeAll { shortcut in
            switch shortcut.target {
            case .action, .visibility:
                return false
            case .region(let rect):
                return !knownRegions.contains(rect)
            }
        }
    }

    /// Forces the preferences the settings page no longer exposes back to their product defaults.
    ///
    /// Placement preview stays on and the island stays on the neutral palette. Older installs may
    /// still carry custom values on disk; SettingsManager applies this on load so those values cannot
    /// leave the user stuck with no UI to reverse them.
    func withProductFixedPreferences() -> SnapConfiguration {
        var copy = self
        copy.showsPreview = true
        copy.islandPalette = .neutral
        return copy
    }
}

// One JSON string keeps `SettingsManager.save(_:for:)` working unchanged and makes the whole
// subsystem resettable by deleting a single key.
//
// Deliberately **not** `RawRepresentable`. The standard library supplies
// `==` for `RawRepresentable where RawValue: Equatable`, and that default wins over the synthesized
// memberwise equality — so two configurations with identical contents would compare as different
// whenever `JSONEncoder` emitted their keys in a different order, which it is free to do and does.
// Named accessors sidestep the trap entirely.
extension SnapConfiguration {

    init?(json: String) {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(SnapConfiguration.self, from: data) else { return nil }
        self = decoded
    }

    var json: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}

// Decoding a stored configuration has to tolerate fields added after the user's copy was written,
// otherwise one new preference wipes every existing choice.
extension SnapConfiguration: Codable {

    private enum CodingKeys: String, CodingKey {
        case edgeOwner, zones, island, showsPreview, honorsRestrictedApps, exclusions
        case shortcuts, customLayouts, savedPlacements, islandLayoutIDs, islandPalette
        case isDockPreviewEnabled, isCommandTabPlusEnabled, isWindowThumbnailsEnabled
        case isDockClickCollapseEnabled
        case isShakeToHideEnabled
    }

    /// The wire format, written out rather than synthesized.
    ///
    /// It is the persisted shape of every window-management preference, so it is worth being able
    /// to read in one place instead of inferring it from the property order.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(edgeOwner, forKey: .edgeOwner)
        try container.encode(zones, forKey: .zones)
        try container.encode(island, forKey: .island)
        try container.encode(showsPreview, forKey: .showsPreview)
        try container.encode(honorsRestrictedApps, forKey: .honorsRestrictedApps)
        try container.encode(exclusions, forKey: .exclusions)
        try container.encode(shortcuts, forKey: .shortcuts)
        try container.encode(customLayouts, forKey: .customLayouts)
        try container.encode(savedPlacements, forKey: .savedPlacements)
        try container.encode(isShakeToHideEnabled, forKey: .isShakeToHideEnabled)
        try container.encode(islandLayoutIDs, forKey: .islandLayoutIDs)
        try container.encode(islandPalette, forKey: .islandPalette)
        try container.encode(isDockPreviewEnabled, forKey: .isDockPreviewEnabled)
        try container.encode(isCommandTabPlusEnabled, forKey: .isCommandTabPlusEnabled)
        try container.encode(isWindowThumbnailsEnabled, forKey: .isWindowThumbnailsEnabled)
        try container.encode(isDockClickCollapseEnabled, forKey: .isDockClickCollapseEnabled)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            edgeOwner: try container.decodeIfPresent(SnapEdgeOwner.self, forKey: .edgeOwner) ?? .lightStats,
            zones: try container.decodeIfPresent(SnapZoneConfiguration.self, forKey: .zones) ?? .default,
            island: try container.decodeIfPresent(SnapIslandConfiguration.self, forKey: .island) ?? .default,
            showsPreview: try container.decodeIfPresent(Bool.self, forKey: .showsPreview) ?? true,
            honorsRestrictedApps: try container.decodeIfPresent(Bool.self, forKey: .honorsRestrictedApps) ?? true,
            exclusions: try container.decodeIfPresent([String].self, forKey: .exclusions) ?? [],
            shortcuts: try container.decodeIfPresent([SnapShortcut].self, forKey: .shortcuts) ?? Self.defaultShortcuts,
            customLayouts: try container.decodeIfPresent([SnapLayout].self, forKey: .customLayouts) ?? [],
            savedPlacements: try container.decodeIfPresent([SnapSavedPlacement].self, forKey: .savedPlacements) ?? [],
            isShakeToHideEnabled: try container.decodeIfPresent(Bool.self, forKey: .isShakeToHideEnabled) ?? true,
            islandLayoutIDs: try container.decodeIfPresent([String].self, forKey: .islandLayoutIDs) ?? Self.defaultIslandLayoutIDs,
            islandPalette: try container.decodeIfPresent(SnapIslandMetrics.Palette.self, forKey: .islandPalette) ?? .neutral,
            isDockPreviewEnabled: try container.decodeIfPresent(Bool.self, forKey: .isDockPreviewEnabled) ?? true,
            isCommandTabPlusEnabled: try container.decodeIfPresent(Bool.self, forKey: .isCommandTabPlusEnabled) ?? true,
            isWindowThumbnailsEnabled: try container.decodeIfPresent(Bool.self, forKey: .isWindowThumbnailsEnabled) ?? false,
            isDockClickCollapseEnabled: try container.decodeIfPresent(Bool.self, forKey: .isDockClickCollapseEnabled) ?? true
        )
        pruneDanglingReferences()
    }
}
