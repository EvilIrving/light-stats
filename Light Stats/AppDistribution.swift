//
//  AppDistribution.swift
//  Light Stats
//
//  Compile-time channel switch between Direct (Developer ID) and Mac App Store.
//  Direct builds leave APP_STORE undefined; AppStore* configurations define it.
//

import Foundation

enum AppDistribution {
    enum Channel: String, Sendable {
        case direct
        case appStore
    }

    #if APP_STORE
    static let channel: Channel = .appStore
    #else
    static let channel: Channel = .direct
    #endif

    static var isAppStore: Bool { channel == .appStore }
    static var isDirect: Bool { channel == .direct }

    // MARK: - Capability gates (MAS free subset)

    static var includesSelfUpdate: Bool { isDirect }
    static var includesLicenseActivation: Bool { isDirect }
    static var includesSMC: Bool { isDirect }
    static var includesAIUsage: Bool { isDirect }
    static var includesWindowManagement: Bool { isDirect }
    static var includesFindMouse: Bool { isDirect }
    static var includesScrollReverse: Bool { isDirect }
    static var includesCleaningMode: Bool { isDirect }
    static var includesKeepAwake: Bool { isDirect }
    static var includesDisplayControl: Bool { isDirect }
    /// Process list + quit/force-quit. Sandbox blocks terminating other apps and
    /// often blocks `/bin/ps`-based enumeration — Direct only.
    static var includesProcessCleanup: Bool { isDirect }
    /// FinderSync right-click actions. Direct only — not part of the MAS monitoring subset.
    static var includesFinderMenu: Bool { isDirect }
    static var includesExitNode: Bool { true }
}
