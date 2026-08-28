import Combine
import Foundation

/// Owns the current license state. Re-validates the stored activation code on launch
/// and whenever `SettingsManager.activationCode` changes; views and coordinators read
/// `isFindMouseUnlocked` instead of touching the raw code.
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    @Published private(set) var payload: LicensePayload?

    var isActivated: Bool { payload != nil }

    /// 现有用户永久授权：升级前已安装的机器自动解锁全部高级功能。
    var isGrandfathered: Bool { settings.isGrandfathered }

    /// 全部高级功能解锁：老用户永久授权，或激活码授予了任意功能。
    var isPremiumUnlocked: Bool {
        isGrandfathered || payload?.features.isEmpty == false
    }

    var isFindMouseUnlocked: Bool {
        isGrandfathered || payload?.features.contains(.findMouse) == true
    }

    private let settings: SettingsManager
    private let validateCode: (String) -> LicensePayload?
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: SettingsManager = .shared,
        validateCode: @escaping (String) -> LicensePayload? = LicenseValidator.validateAppCode
    ) {
        self.settings = settings
        self.validateCode = validateCode
        reload(settings.activationCode)
        settings.$activationCode
            .dropFirst()
            .sink { [weak self] code in self?.reload(code) }
            .store(in: &cancellables)
    }

    /// Validates and stores a code. Returns false when the code is invalid.
    @discardableResult
    func activate(_ rawCode: String) -> Bool {
        let code = LicenseCodec.normalize(rawCode)
        guard let validated = validateCode(code) else { return false }
        settings.activationCode = code
        payload = validated
        return true
    }

    func deactivate() {
        settings.activationCode = nil
        payload = nil
    }

    private func reload(_ code: String?) {
        guard let code else {
            payload = nil
            return
        }
        payload = validateCode(code)
    }
}
