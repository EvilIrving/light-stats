import SwiftUI

struct FinderMenuTemplatesSection: View {
    @ObservedObject var store: FinderMenuConfigStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditableListView(
                title: "settings.finderMenu.customTemplates".localized,
                rows: store.config.templates.map {
                    EditableListRow(id: $0.id, title: $0.title,
                                    subtitle: $0.fileExtension.isEmpty ? "" : ".\($0.fileExtension)")
                },
                emptyHint: "settings.finderMenu.customTemplatesHint".localized,
                onAdd: { store.addTemplate() },
                onRemove: { id in
                    guard let template = store.config.templates.first(where: { $0.id == id }) else { return }
                    store.removeTemplate(template)
                }
            )
            .disabled(store.isImportingTemplate)
            if store.isImportingTemplate {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("settings.finderMenu.importingTemplate".localized)
                }
                .font(.system(size: 11))
            }
            if let error = store.templateError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
