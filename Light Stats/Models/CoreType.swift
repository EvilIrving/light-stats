import SwiftUI

enum CoreType {
    case performance
    case efficiency
    case unknown

    var label: String {
        switch self {
        case .performance: return "P"
        case .efficiency: return "E"
        case .unknown: return ""
        }
    }

    var color: Color {
        switch self {
        case .performance: return .orange
        case .efficiency: return .blue
        case .unknown: return .gray
        }
    }
}
