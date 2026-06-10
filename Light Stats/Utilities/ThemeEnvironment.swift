import SwiftUI

struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .classic
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
