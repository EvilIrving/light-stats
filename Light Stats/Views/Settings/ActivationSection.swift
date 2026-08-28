import SwiftUI

/// 软件更新组内的激活行：不创建独立分组或卡片。
struct ActivationSection: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var license = LicenseManager.shared
    @State private var codeInput = ""
    @State private var showInvalidError = false

    var body: some View {
        if license.isActivated {
            activatedRow
        } else if license.isGrandfathered {
            grandfatheredRow
        } else {
            entryRow
        }
    }

    private var activatedRow: some View {
        SettingsRow(
            "settings.activation".localized,
            subtitle: activatedSummary
        ) {
            HStack(spacing: 10) {
                if license.isPremiumUnlocked {
                    proText
                }
                Button("settings.activation.remove".localized, action: license.deactivate)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.red)
            }
        }
    }

    /// 现有用户自动享有永久授权，无需任何操作。
    private var grandfatheredRow: some View {
        SettingsRow(
            "settings.activation.grandfathered".localized,
            subtitle: "settings.activation.grandfathered.hint".localized
        ) {
            proText
        }
    }

    private var entryRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(
                "settings.activation".localized,
                subtitle: "settings.activation.hint".localized
            ) {
                HStack(spacing: 8) {
                    TextField("settings.activation.enterCode".localized, text: $codeInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 230)
                        .autocorrectionDisabled()
                        .onSubmit(activate)
                    Button("settings.activation.activate".localized, action: activate)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(trimmedCode.isEmpty)
                }
            }
            if showInvalidError {
                Text("settings.activation.invalid".localized)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 9)
            }
        }
    }

    private var proText: some View {
        Text("Pro")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.accent)
    }

    private var trimmedCode: String {
        codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activatedSummary: String {
        guard let payload = license.payload else { return "" }
        return [payload.owner, featureNames, issuedDateString]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var featureNames: String {
        license.payload?.features
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            .joined(separator: ", ") ?? ""
    }

    private var issuedDateString: String {
        guard let issuedAt = license.payload?.issuedAt else { return "" }
        return Self.issuedFormatter.string(from: issuedAt)
    }

    private func activate() {
        guard license.activate(trimmedCode) else {
            showInvalidError = true
            return
        }
        showInvalidError = false
        codeInput = ""
        ToastCenter.shared.show(
            message: "settings.activation.successToast".localized,
            systemImage: "checkmark.seal.fill",
            tint: .green,
            duration: 3
        )
    }

    private static let issuedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

extension LicensePayload.Feature {
    var displayName: String {
        switch self {
        case .findMouse: return "settings.activation.feature.findMouse".localized
        }
    }
}
