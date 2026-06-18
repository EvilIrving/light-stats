//
//  CleaningModeOverlayView.swift
//  Light Stats
//
//  清洁模式遮罩内容：图标 + 提示文案 + 倒计时 + 鼠标可点的「结束」按钮
//  （唯一的手动退出路径，键盘已被锁定，不能依赖键盘手势）。
//

import SwiftUI

struct CleaningModeOverlayView: View {
    @ObservedObject var viewModel: CleaningModeViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image("cleaningLock")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundColor(.white)

            Text("cleaning.overlay.title".localized)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)

            Text("cleaning.overlay.remaining".localized(viewModel.remainingSeconds))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .monospacedDigit()

            Button {
                viewModel.requestEarlyStop()
            } label: {
                Text("cleaning.overlay.stop".localized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .focusable(false)
    }
}
