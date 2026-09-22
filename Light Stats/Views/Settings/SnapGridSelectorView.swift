//
//  SnapGridSelectorView.swift
//  Light Stats
//

import SwiftUI

struct SnapGridSelectorView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var draft: SnapLayoutDraft
    var savedRects: Set<SnapNormalizedRect> = []
    let onSavePosition: (SnapNormalizedRect) -> Void
    @State private var pending: SnapNormalizedRect?
    @State private var replacingID: String?
    @State private var gestureStarted = false
    @State private var resizing = false

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                let bounds = CGRect(origin: .zero, size: proxy.size)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6).fill(theme.wellFill)
                    gridLines(in: bounds)
                    ForEach(draft.segments) { segment in
                        tile(segment.rect, selected: draft.selectedID == segment.id, in: bounds)
                            .opacity(replacingID == segment.id && pending != nil ? 0.25 : 1)
                    }
                    if let pending {
                        tile(pending, selected: true, in: bounds, valid: draft.accepts(pending, replacing: replacingID))
                            .allowsHitTesting(false)
                    }
                    if let selected = draft.selected, pending == nil {
                        let frame = frame(selected.rect, in: bounds)
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 22, height: 22)
                            .background(.regularMaterial, in: Circle())
                            .position(x: frame.maxX - 11, y: frame.maxY - 11)
                            .gesture(resizeGesture(selected, in: bounds))
                            .accessibilityLabel("settings.snap.editor.resize".localized)
                    }
                }
                .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(editGesture(in: bounds))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.surfaceStroke, lineWidth: 1))
            }
            .aspectRatio(SnapLayoutProjection.referenceAspect, contentMode: .fit)
            .frame(maxHeight: 240)
            HStack(spacing: 12) {
                Button { draft.selectedID = nil } label: { Image(systemName: "plus") }
                    .accessibilityLabel("settings.snap.editor.add".localized)
                Button { animate { draft.undo() } } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!draft.canUndo)
                    .accessibilityLabel("settings.snap.editor.undo".localized)
                Button { animate { draft.removeSelected() } } label: { Image(systemName: "trash") }
                    .disabled(draft.selected == nil)
                    .accessibilityLabel("settings.snap.editor.remove".localized)
                Spacer()
                Button {
                    guard let selected = draft.selected else { return }
                    onSavePosition(selected.rect)
                } label: { Image(systemName: isPositionSaved ? "bookmark.fill" : "bookmark") }
                    .disabled(draft.selected == nil || isPositionSaved)
                    .accessibilityLabel("settings.snap.editor.savePosition".localized)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 4)
        }
    }

    private var isPositionSaved: Bool {
        draft.selected.map { savedRects.contains($0.rect) } ?? false
    }

    private func frame(_ rect: SnapNormalizedRect, in bounds: CGRect) -> CGRect {
        SnapGridGeometry.frame(for: rect, in: bounds, margins: .zero)
    }

    private func tile(_ rect: SnapNormalizedRect, selected: Bool, in bounds: CGRect, valid: Bool = true) -> some View {
        let frame = frame(rect, in: bounds)
        let color = valid ? theme.accent : theme.signalWarn
        return RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(selected ? 0.22 : 0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 3).strokeBorder(color.opacity(selected ? 0.9 : 0.4), lineWidth: selected ? 1.5 : 0.75)
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
    }

    private func gridLines(in bounds: CGRect) -> some View {
        Path { path in
            for index in 1..<8 {
                let fraction = CGFloat(index) / 8
                path.move(to: CGPoint(x: bounds.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: bounds.width * fraction, y: bounds.height))
                path.move(to: CGPoint(x: 0, y: bounds.height * fraction))
                path.addLine(to: CGPoint(x: bounds.width, y: bounds.height * fraction))
            }
        }
        .stroke(theme.surfaceStroke, style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        .allowsHitTesting(false)
    }

    private func editGesture(in bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !resizing else { return }
                if !gestureStarted {
                    gestureStarted = true
                    replacingID = draft.segments.first { frame($0.rect, in: bounds).contains(value.startLocation) }?.id
                    draft.selectedID = replacingID
                }
                if let original = draft.segments.first(where: { $0.id == replacingID }) {
                    pending = SnapLayoutDraft.moved(
                        original.rect,
                        columns: Int((value.translation.width / bounds.width * 8).rounded()),
                        rows: Int((value.translation.height / bounds.height * 8).rounded())
                    )
                } else {
                    var selection = SnapGridSelection()
                    selection.begin(at: cell(value.startLocation, in: bounds))
                    selection.extend(to: cell(value.location, in: bounds))
                    pending = selection.rect
                }
            }
            .onEnded { _ in
                guard !resizing else { return }
                finishGesture()
            }
    }

    private func resizeGesture(_ segment: SnapSegment, in bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                resizing = true
                replacingID = segment.id
                pending = SnapLayoutDraft.resized(
                    segment.rect,
                    columns: Int((value.translation.width / bounds.width * 8).rounded()),
                    rows: Int((value.translation.height / bounds.height * 8).rounded())
                )
            }
            .onEnded { _ in finishGesture() }
    }

    private func finishGesture() {
        animate {
            if let pending { draft.put(pending, replacing: replacingID) }
            pending = nil
            replacingID = nil
            gestureStarted = false
            resizing = false
        }
    }

    private func cell(_ point: CGPoint, in bounds: CGRect) -> SnapGridCell {
        SnapGridCell(column: Int(point.x / max(bounds.width, 1) * 8), row: Int(point.y / max(bounds.height, 1) * 8))
    }

    private func animate(_ action: () -> Void) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.08 : 0.18), action)
    }
}
