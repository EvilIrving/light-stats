import SwiftUI

struct BatteryChargeRangeSlider: View {
    @Binding var lowerValue: Int
    @Binding var upperValue: Int

    private enum Handle {
        case lower
        case upper
    }

    private let minimumValue = BatteryControlLimits.minimumLower
    private let maximumValue = BatteryControlLimits.maximumUpper
    private let step = 5
    private let minimumGap = BatteryControlLimits.minimumGap
    private let handleRadius: CGFloat = 7
    @State private var draggingHandle: Handle?

    var body: some View {
        HStack(spacing: 8) {
            valueText(lowerValue, alignment: .trailing)
            sliderTrack
            valueText(upperValue, alignment: .leading)
        }
        .frame(height: 24)
    }

    private var sliderTrack: some View {
        GeometryReader { geometry in
            let usableWidth = max(geometry.size.width - handleRadius * 2, 1)
            let lowerX = xPosition(for: lowerValue, usableWidth: usableWidth)
            let upperX = xPosition(for: upperValue, usableWidth: usableWidth)
            let trackY = geometry.size.height / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 4)
                    .padding(.horizontal, handleRadius)

                Capsule()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: max(upperX - lowerX, 4), height: 4)
                    .offset(x: lowerX)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: handleRadius * 2, height: handleRadius * 2)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                    .position(x: lowerX, y: trackY)
                    .accessibilityLabel("settings.batteryProtection.lowerLimit".localized)
                    .accessibilityValue(String(lowerValue) + "%")

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: handleRadius * 2, height: handleRadius * 2)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                    .position(x: upperX, y: trackY)
                    .accessibilityLabel("settings.batteryProtection.upperLimit".localized)
                    .accessibilityValue(String(upperValue) + "%")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if draggingHandle == nil {
                            draggingHandle = abs(value.startLocation.x - lowerX)
                                <= abs(value.startLocation.x - upperX) ? .lower : .upper
                        }
                        update(valueAt(x: value.location.x, usableWidth: usableWidth))
                    }
                    .onEnded { _ in
                        draggingHandle = nil
                    }
            )
        }
        .frame(height: 24)
        .accessibilityElement(children: .contain)
    }

    private func valueText(_ value: Int, alignment: Alignment) -> some View {
        Text(String(value) + "%")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.primary)
            .frame(width: 32, alignment: alignment)
    }

    private func xPosition(for value: Int, usableWidth: CGFloat) -> CGFloat {
        let progress = CGFloat(value - minimumValue) / CGFloat(maximumValue - minimumValue)
        return handleRadius + min(max(progress, 0), 1) * usableWidth
    }

    private func valueAt(x: CGFloat, usableWidth: CGFloat) -> Int {
        let progress = min(max((x - handleRadius) / usableWidth, 0), 1)
        let rawValue = CGFloat(minimumValue) + progress * CGFloat(maximumValue - minimumValue)
        let stepped = ((rawValue - CGFloat(minimumValue)) / CGFloat(step)).rounded()
        return minimumValue + Int(stepped) * step
    }

    private func update(_ candidate: Int) {
        switch draggingHandle {
        case .lower:
            lowerValue = min(max(candidate, minimumValue), upperValue - minimumGap)
        case .upper:
            upperValue = max(min(candidate, maximumValue), lowerValue + minimumGap)
        case .none:
            break
        }
    }
}
