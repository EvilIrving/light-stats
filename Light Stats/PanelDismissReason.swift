import Foundation

enum PanelDismissReason: String {
    case resignKey
    case globalMouseDown
    case statusItemToggle
    case externalRequest

    var isAutomatic: Bool {
        switch self {
        case .resignKey, .globalMouseDown:
            return true
        case .statusItemToggle, .externalRequest:
            return false
        }
    }
}
