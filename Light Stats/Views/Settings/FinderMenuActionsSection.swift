import SwiftUI

struct FinderMenuActionsSection: View {
    @ObservedObject var store: FinderMenuConfigStore

    var body: some View {
        DisclosureGroup("settings.finderMenu.visibleActions".localized) {
            SettingsGroup {
                ForEach(Array(FinderMenuAction.configurableActions.enumerated()), id: \.element) { index, action in
                    if index > 0 { rowDivider() }
                    SettingsRow("findermenu.menu.\(action.rawValue)".localized) {
                        SettingsToggle(isOn: Binding(
                            get: { store.config.isActionEnabled(action) },
                            set: { store.setAction(action, enabled: $0) }
                        ))
                    }
                }
            }
            .padding(.top, 8)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
    }
}
