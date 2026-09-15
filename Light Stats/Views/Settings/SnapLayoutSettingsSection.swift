//
//  SnapLayoutSettingsSection.swift
//  Light Stats
//

import SwiftUI
import UniformTypeIdentifiers

struct SnapLayoutSettingsSection: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var settings: SettingsManager
    @State private var draft = SnapLayoutDraft()
    @State private var title = ""
    @State private var editingID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection("settings.snap.layouts.title".localized) {
                VStack(spacing: 4) {
                    HStack {
                        Spacer()
                        Button { resetEditor() } label: { Image(systemName: "plus") }
                            .accessibilityLabel("settings.snap.layouts.create".localized)
                        Button {
                            mutate { $0.islandLayoutIDs = SnapConfiguration.defaultIslandLayoutIDs }
                        } label: { Image(systemName: "arrow.counterclockwise") }
                            .accessibilityLabel("settings.snap.editor.resetOrder".localized)
                    }
                    .buttonStyle(.borderless)
                    ForEach(orderedLayouts) { layout in
                        layoutRow(layout)
                    }
                }
            }
            SettingsSection("settings.snap.editor.title".localized) {
                VStack(spacing: 12) {
                    SnapGridSelectorView(draft: $draft, savedRects: Set(settings.windowSnap.savedPlacements.map(\.rect))) { rect in
                        mutate { SnapLayoutEditing.savePosition(rect, title: resolvedTitle, in: &$0) }
                    }
                    HStack {
                        TextField("settings.snap.newLayoutName".localized, text: $title)
                            .textFieldStyle(.roundedBorder)
                        Button("settings.snap.editor.save".localized) { saveLayout() }
                            .disabled(draft.segments.isEmpty)
                        if editingID != nil {
                            Button { resetEditor() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("settings.snap.editor.cancel".localized)
                        }
                    }
                    .controlSize(.small)
                }
            }
            if !settings.windowSnap.savedPlacements.isEmpty {
                SettingsSection("settings.snap.placements.title".localized) {
                    VStack(spacing: 8) {
                        ForEach(settings.windowSnap.savedPlacements) { placement in
                            placementRow(placement)
                        }
                    }
                }
            }
        }
    }

    private var orderedLayouts: [SnapLayout] {
        let pinned = settings.windowSnap.islandLayouts
        let ids = Set(pinned.map(\.id))
        return pinned + settings.windowSnap.allLayouts.filter { !ids.contains($0.id) }
    }

    private func layoutRow(_ layout: SnapLayout) -> some View {
        let pinned = settings.windowSnap.islandLayoutIDs.contains(layout.id)
        return HStack(spacing: 12) {
            Button { edit(layout) } label: {
                HStack(spacing: 12) {
                    SnapLayoutPreview(layout: layout, margins: settings.windowSnap.margins, ink: theme.inkPrimary)
                        .frame(width: 76, height: 48)
                    Text(SnapIslandText.title(for: layout))
                        .font(.system(size: 12, weight: editingID == layout.id ? .semibold : .regular))
                        .foregroundStyle(theme.inkPrimary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                mutate { configuration in
                    if pinned {
                        configuration.islandLayoutIDs.removeAll { $0 == layout.id }
                    } else {
                        configuration.islandLayoutIDs.append(layout.id)
                    }
                }
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .foregroundStyle(pinned ? theme.accent : theme.inkSecondary)
            }
            .accessibilityLabel("settings.snap.editor.pin".localized)
            if !layout.isBuiltIn {
                Button {
                    mutate { SnapLayoutEditing.removeLayout(layout.id, in: &$0) }
                    if editingID == layout.id { resetEditor() }
                } label: { Image(systemName: "trash") }
                    .accessibilityLabel("settings.snap.layouts.delete".localized)
            }
            Image(systemName: "line.3.horizontal").foregroundStyle(theme.inkSecondary)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .draggable(layout.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, pinned, settings.windowSnap.islandLayoutIDs.contains(id) else { return false }
            mutate { SnapLayoutEditing.move(id, before: layout.id, in: &$0) }
            return true
        }
        .contextMenu {
            Button("settings.snap.editor.edit".localized) { edit(layout) }
            if pinned, let index = settings.windowSnap.islandLayoutIDs.firstIndex(of: layout.id), index > 0 {
                Button("settings.snap.editor.moveUp".localized) {
                    let previous = settings.windowSnap.islandLayoutIDs[index - 1]
                    mutate { SnapLayoutEditing.move(layout.id, before: previous, in: &$0) }
                }
            }
        }
    }

    private func placementRow(_ placement: SnapSavedPlacement) -> some View {
        let target = SnapTarget.region(placement.rect)
        return HStack(spacing: 12) {
            Button {
                draft = SnapLayoutDraft(segments: [SnapSegment(id: UUID().uuidString, title: "", rect: placement.rect)])
                title = placement.title
                editingID = nil
            } label: {
                SnapLayoutPreview(
                    layout: SnapLayout(id: placement.id, title: placement.title, isBuiltIn: false,
                                       segments: [SnapSegment(id: placement.id, title: "", rect: placement.rect)]),
                    margins: settings.windowSnap.margins, ink: theme.inkPrimary
                )
                .frame(width: 76, height: 48)
            }
            .buttonStyle(.plain)
            Text(placement.title).font(.system(size: 12)).lineLimit(1)
            Spacer()
            KeyComboRecorder(
                keyCode: settings.windowSnap.shortcut(for: target).keyCode,
                modifiers: settings.windowSnap.shortcut(for: target).modifiers,
                onRecord: { code, modifiers in
                    mutate { $0.setShortcut(SnapShortcut(target: target, keyCode: code, modifiers: modifiers)) }
                },
                onClear: { mutate { $0.removeShortcut(for: target) } }
            )
            Button { mutate { SnapLayoutEditing.removePosition(placement.id, in: &$0) } } label: { Image(systemName: "trash") }
                .accessibilityLabel("settings.snap.placements.delete".localized)
        }
        .buttonStyle(.borderless)
    }

    private var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "settings.snap.defaultLayoutName".localized(settings.windowSnap.customLayouts.count + 1) : trimmed
    }

    private func edit(_ layout: SnapLayout) {
        editingID = layout.isBuiltIn ? nil : layout.id
        title = SnapIslandText.title(for: layout)
        draft = SnapLayoutDraft(segments: layout.segments)
    }

    private func resetEditor() {
        editingID = nil
        title = ""
        draft = SnapLayoutDraft()
    }

    private func saveLayout() {
        let layout = SnapLayout(
            id: editingID ?? "custom-\(UUID().uuidString)", title: resolvedTitle, isBuiltIn: false, segments: draft.segments
        )
        mutate { SnapLayoutEditing.save(layout, in: &$0) }
        editingID = layout.id
    }

    private func mutate(_ action: (inout SnapConfiguration) -> Void) {
        var configuration = settings.windowSnap
        action(&configuration)
        withAnimation(.easeOut(duration: reduceMotion ? 0.08 : 0.2)) { settings.windowSnap = configuration }
    }
}
