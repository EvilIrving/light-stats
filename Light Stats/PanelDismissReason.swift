import Foundation

enum PanelDismissReason: String {
    case resignKey
    case resignActive
    case globalMouseDown
    case localMouseDown
    case statusItemToggle
    case hotkeyToggle
    case externalRequest

    var isAutomatic: Bool {
        switch self {
        case .resignKey, .resignActive, .globalMouseDown, .localMouseDown:
            return true
        case .statusItemToggle, .hotkeyToggle, .externalRequest:
            return false
        }
    }
}
