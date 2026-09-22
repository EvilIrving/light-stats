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
    @State private var hoveredID: String?

    /// 四列：设置页内宽刚好把八个内置布局排成两行，而缩略图仍然大到能一眼分清
    /// 「左侧堆叠」和「右侧堆叠」。列数减少会把卡片拉成巨幅占位图。
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    /// The 8×8 editor is not finished, so its section is not drawn and the two controls that only
    /// feed it stop responding.
    ///
    /// Nothing behind it changes: built-in and custom layouts, pinning, ordering, saved placements,
    /// the island's tiles, and placement all behave exactly as they do with the editor drawn. This is
    /// a visibility switch, not a feature switch — flipping it back is the whole restore.
    private static let showsEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection("settings.snap.layouts.title".localized, accessory: { resetOrderButton }) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(orderedLayouts) { layout in
                        layoutCard(layout)
                    }
                }
            }
            if Self.showsEditor {
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
                            // 编辑器里有东西就显示：不论是改自建布局，还是刚把一个内置布局装进来
                            // 想重新开始，都靠它回到空白。
                            if !draft.segments.isEmpty {
                                Button { resetEditor() } label: { Image(systemName: "xmark") }
                                    .accessibilityLabel("settings.snap.editor.cancel".localized)
                            }
                        }
                        .controlSize(.small)
                    }
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

    /// 恢复默认排列。放在分组标题行右侧，不占据卡片网格本身的位置。
    private var resetOrderButton: some View {
        Button {
            mutate { $0.islandLayoutIDs = SnapConfiguration.defaultIslandLayoutIDs }
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("settings.snap.editor.resetOrder".localized)
        .help("settings.snap.editor.resetOrder".localized)
    }

    /// 一张布局卡片：只有缩略图。右上角钉选，自建布局悬停时左上角出现删除。
    /// 点它把布局装进下面的编辑器，和旧列表行为一致。
    private func layoutCard(_ layout: SnapLayout) -> some View {
        let pinned = settings.windowSnap.islandLayoutIDs.contains(layout.id)
        // 编辑器藏起来时，点卡片不再有可见效果：「装进编辑器」这件事本身是看不见的。
        let isEditing = Self.showsEditor && editingID == layout.id
        let name = SnapIslandText.title(for: layout)
        return Button { guard Self.showsEditor else { return }; edit(layout) } label: {
            // 不显示布局名：缩略图本身就是标识，「左侧堆叠」和「右侧堆叠」一眼就能分开。名字
            // 留在无障碍标签和悬停提示里，自建布局不会被读成无名之物。
            SnapLayoutPreview(layout: layout, ink: theme.inkPrimary)
                .aspectRatio(SnapLayoutProjection.referenceAspect, contentMode: .fit)
                // 顶部给钉选/删除留一行，缩略图不会被图标压住。
                .padding(.horizontal, 10)
                .padding(.top, 26)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 容器只在需要时出现：悬停给一点落点反馈，正在编辑才染色描边。静止状态下布局就是
        // 缩略图本身，不再套一层没有信息量的方框。
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isEditing ? theme.accent.opacity(0.14) : (hoveredID == layout.id ? theme.rowHoverFill : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isEditing ? theme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) { pinButton(layout, pinned: pinned, name: name) }
        .overlay(alignment: .topLeading) { deleteButton(layout) }
        .onHover { hovering in
            if hovering {
                hoveredID = layout.id
            } else if hoveredID == layout.id {
                hoveredID = nil
            }
        }
        .help(name)
        .draggable(layout.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, pinned, settings.windowSnap.islandLayoutIDs.contains(id) else { return false }
            mutate { SnapLayoutEditing.move(id, before: layout.id, in: &$0) }
            return true
        }
        .contextMenu {
            if Self.showsEditor {
                Button("settings.snap.editor.edit".localized) { edit(layout) }
            }
            if pinned, let index = settings.windowSnap.islandLayoutIDs.firstIndex(of: layout.id), index > 0 {
                Button("settings.snap.editor.moveUp".localized) {
                    let previous = settings.windowSnap.islandLayoutIDs[index - 1]
                    mutate { SnapLayoutEditing.move(layout.id, before: previous, in: &$0) }
                }
            }
            if !layout.isBuiltIn {
                Divider()
                Button("settings.snap.layouts.delete".localized, role: .destructive) { remove(layout) }
            }
        }
    }

    private func pinButton(_ layout: SnapLayout, pinned: Bool, name: String) -> some View {
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
                .font(.system(size: 11))
                .foregroundStyle(pinned ? theme.accent : theme.inkSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(name) + Text(verbatim: ", ") + Text("settings.snap.editor.pin".localized))
        .help("settings.snap.editor.pin".localized)
    }

    /// 只对自建布局显示删除，且只在悬停或正在编辑时出现，卡片静止的样子保持干净。
    @ViewBuilder
    private func deleteButton(_ layout: SnapLayout) -> some View {
        if !layout.isBuiltIn, hoveredID == layout.id || editingID == layout.id {
            Button { remove(layout) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("settings.snap.layouts.delete".localized)
        }
    }

    private func remove(_ layout: SnapLayout) {
        mutate { SnapLayoutEditing.removeLayout(layout.id, in: &$0) }
        if editingID == layout.id { resetEditor() }
    }

    private func placementRow(_ placement: SnapSavedPlacement) -> some View {
        let target = SnapTarget.region(placement.rect)
        return HStack(spacing: 12) {
            Button {
                guard Self.showsEditor else { return }
                draft = SnapLayoutDraft(segments: [SnapSegment(id: UUID().uuidString, title: "", rect: placement.rect)])
                title = placement.title
                editingID = nil
            } label: {
                SnapLayoutPreview(
                    layout: SnapLayout(id: placement.id, title: placement.title, isBuiltIn: false,
                                       segments: [SnapSegment(id: placement.id, title: "", rect: placement.rect)]),
                    ink: theme.inkPrimary
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
