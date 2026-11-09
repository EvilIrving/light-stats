//
//  PermissionGuideCardView.swift
//  Light Stats
//

import SwiftUI

/// The guide card: a sentence, an arrow pointing at the list, and the icon to drag.
struct PermissionGuideCardView: View {

    /// The drawn card. The flight interpolates this rectangle, so it is also the panel's content
    /// size minus `chromeInset` on each side.
    static let cardSize = CGSize(width: 468, height: 104)

    /// Margin between the card and the panel's frame, where the shadow is drawn.
    ///
    /// A window clips its own content to its own frame, so a shadow with no margin around it is cut
    /// off at the edge — which reads as a hard border, not as depth.
    static let chromeInset: CGFloat = 22

    let state: PermissionGuideCardState

    var body: some View {
        row
            .padding(.horizontal, 18)
            .frame(width: Self.cardSize.width, height: Self.cardSize.height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: state.cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: state.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
            // Two passes only: a wide soft one for height, a tight one to sit the card on the
            // window behind it. `.compositingGroup` keeps them from doubling at the corners.
            .compositingGroup()
            .shadow(color: .black.opacity(0.22 * state.shadowOpacity), radius: 15, y: -6)
            .shadow(color: .black.opacity(0.18 * state.shadowOpacity), radius: 2, y: 0)
            .padding(Self.chromeInset)
    }

    private var row: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 5) {
                Text(instruction)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: state.onBack) {
                    Text("permission.guide.back".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state.phase {
        case .guiding:
            if let url = state.dropBundleURL {
                DragAppIconView(url: url)
                    .frame(width: 52, height: 52)
                    .accessibilityLabel("permission.guide.dragIcon".localized)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                    .frame(width: 52, height: 52)
            }
        case .relaunchRequired:
            Button("settings.snap.screenRecording.relaunch".localized, action: state.onRelaunch)
                .controlSize(.regular)
        }
    }

    /// Which way the list lies from the card.
    private var glyph: String {
        switch state.side {
        case .below: return "arrow.up"
        case .above: return "arrow.down"
        case .left: return "arrow.right"
        case .right: return "arrow.left"
        }
    }

    private var instruction: String {
        switch state.phase {
        case .relaunchRequired:
            return "permission.guide.relaunchRequired".localized
        case .guiding:
            guard state.dropBundleURL != nil else {
                return "permission.guide.bundleUnavailable".localized
            }
            return state.side.instructionKey.localized(state.appName, state.pane.displayNameKey.localized)
        }
    }
}
