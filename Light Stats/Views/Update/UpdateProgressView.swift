//
//  UpdateProgressView.swift
//  Light Stats
//
//  更新下载/安装阶段的极简进度窗口，观察 UpdateManager.phase。
//

import SwiftUI

struct UpdateProgressView: View {
    @ObservedObject var manager: UpdateManager
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            switch manager.phase {
            case .downloading(let fraction):
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            default:
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .id(localization.currentLanguage)
        .focusable(false)
    }

    private var title: String {
        switch manager.phase {
        case .installing: return "update.progress.installing".localized
        default: return "update.progress.downloading".localized
        }
    }
}
