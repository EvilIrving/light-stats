import Combine
import Foundation
import ServiceManagement

@MainActor
final class BatteryChargeControlManager: ObservableObject {
    private struct ConfigureOperation {
        let id: UUID
        let generation: Int
    }

    private struct ResetOperation {
        let id: UUID
        let generation: Int
        let remainingAttempts: Int
        let revertOnFailure: Bool
        let completion: (@MainActor (Bool) -> Void)?
    }

    static let shared = BatteryChargeControlManager()

    static var privilegedLifecycleAllowed: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] == nil
            && environment["XCTestBundlePath"] == nil
    }

    @Published private(set) var snapshot = BatteryChargeControlSnapshot.inactive
    @Published private(set) var helperStatus: SMAppService.Status = .notRegistered

    private let log = AppLogger(category: "BatteryControl")
    private var connection: NSXPCConnection?
    private var synchronizeTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var disableRetryTask: Task<Void, Never>?
    private var configureRetryTask: Task<Void, Never>?
    private var configureTimeoutTask: Task<Void, Never>?
    private var resetTimeoutTask: Task<Void, Never>?
    private var activeConfigureOperation: ConfigureOperation?
    private var activeResetOperation: ResetOperation?
    private var controlEnabled = false
    private var desiredUpperLimit = BatteryControlLimits.defaultUpper
    private var desiredLowerLimit = BatteryControlLimits.defaultLower
    private var transitionGeneration = 0
    private var requestRevision: Int64 = 0
    private var didOpenApprovalSettings = false
    private var isPreparingTermination = false

    private init() {}

    func synchronize(enabled: Bool, upperLimit: Int, lowerLimit: Int) {
        guard !isPreparingTermination else { return }
        controlEnabled = enabled
        desiredUpperLimit = upperLimit
        desiredLowerLimit = lowerLimit
        transitionGeneration += 1
        let generation = transitionGeneration

        synchronizeTask?.cancel()
        configureRetryTask?.cancel()

        guard enabled else {
            applyDisabled(generation: generation)
            return
        }

        synchronizeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            guard let self, self.isCurrent(generation, enabled: true) else { return }
            self.applyEnabled(generation: generation)
        }
    }

    func applicationDidBecomeActive() {
        guard !isPreparingTermination, controlEnabled else { return }
        transitionGeneration += 1
        applyEnabled(generation: transitionGeneration)
    }

    func prepareForTermination(completion: @escaping @MainActor (Bool) -> Void) {
        guard !isPreparingTermination else {
            completion(false)
            return
        }
        isPreparingTermination = true
        synchronizeTask?.cancel()
        configureRetryTask?.cancel()
        disableRetryTask?.cancel()
        stopStatusPolling()

        guard !controlEnabled else {
            shutdown()
            completion(true)
            return
        }

        transitionGeneration += 1
        let generation = transitionGeneration
        resetAndUnregister(
            remainingAttempts: 2,
            generation: generation,
            revertOnFailure: false
        ) { [weak self] success in
            guard let self else {
                completion(false)
                return
            }
            if success {
                self.shutdown()
            } else {
                self.isPreparingTermination = false
                self.transitionGeneration += 1
                self.applyDisabled(generation: self.transitionGeneration)
            }
            completion(success)
        }
    }

    func shutdown() {
        isPreparingTermination = false
        synchronizeTask?.cancel()
        statusTask?.cancel()
        statusTask = nil
        disableRetryTask?.cancel()
        configureRetryTask?.cancel()
        configureTimeoutTask?.cancel()
        resetTimeoutTask?.cancel()
        activeConfigureOperation = nil
        activeResetOperation = nil
        connection?.invalidate()
        connection = nil
    }

    private func applyEnabled(generation: Int) {
        guard isCurrent(generation, enabled: true) else { return }
        disableRetryTask?.cancel()
        snapshot.upperLimit = desiredUpperLimit
        snapshot.lowerLimit = desiredLowerLimit

        guard DeviceCapabilities.isPortable else {
            snapshot.status = .unavailable
            snapshot.helperAvailable = false
            snapshot.errorMessage = "battery.control.unsupportedDevice".localized
            return
        }

        do {
            try registerHelper()
            guard isCurrent(generation, enabled: true) else { return }
            configureHelper(generation: generation)
        } catch BatteryControlManagerError.requiresApproval {
            snapshot.status = .error
            snapshot.helperAvailable = false
            snapshot.errorMessage = "battery.control.approvalRequired".localized
        } catch {
            snapshot.status = .error
            snapshot.helperAvailable = false
            snapshot.errorMessage = error.localizedDescription
            log.error("Unable to register battery helper: \(error.localizedDescription)")
        }
    }

    private func applyDisabled(generation: Int) {
        guard isCurrent(generation, enabled: false) else { return }
        clearActiveConfigureOperation()
        stopStatusPolling()
        resetAndUnregister(
            remainingAttempts: 3,
            generation: generation,
            revertOnFailure: true,
            completion: nil
        )
    }

    private func registerHelper() throws {
        let service = helperService
        helperStatus = service.status
        switch service.status {
        case .enabled:
            didOpenApprovalSettings = false
            snapshot.helperAvailable = true
        case .notRegistered, .notFound:
            do {
                try service.register()
            } catch {
                helperStatus = service.status
                let registrationError = error as NSError
                if helperStatus == .requiresApproval
                    || (registrationError.domain == NSPOSIXErrorDomain
                        && registrationError.code == Int(EPERM)) {
                    openApprovalSettings()
                    throw BatteryControlManagerError.requiresApproval
                }
                throw error
            }
            helperStatus = service.status
            if helperStatus == .requiresApproval {
                openApprovalSettings()
                throw BatteryControlManagerError.requiresApproval
            }
            guard helperStatus == .enabled else {
                throw BatteryControlManagerError.registrationFailed
            }
            didOpenApprovalSettings = false
            snapshot.helperAvailable = true
        case .requiresApproval:
            openApprovalSettings()
            throw BatteryControlManagerError.requiresApproval
        @unknown default:
            throw BatteryControlManagerError.registrationFailed
        }
    }

    private func configureHelper(generation: Int) {
        guard isCurrent(generation, enabled: true) else { return }
        guard let proxy = remoteProxy() else {
            snapshot.status = .error
            snapshot.errorMessage = "battery.control.helperUnavailable".localized
            scheduleConfigureRetry(generation: generation)
            return
        }

        let operation = ConfigureOperation(id: UUID(), generation: generation)
        activeConfigureOperation = operation
        configureTimeoutTask?.cancel()
        helperMayBeControlling = true
        configureTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
            self?.handleConfigureTransportFailure(
                operationID: operation.id,
                message: "battery.control.helperUnavailable".localized
            )
        }

        proxy.configure(
            enabled: true,
            upperLimit: desiredUpperLimit,
            lowerLimit: desiredLowerLimit,
            revision: nextRequestRevision()
        ) { [weak self] success, errorMessage in
            Task { @MainActor in
                guard let self,
                      self.finishConfigureOperation(operation.id),
                      self.isCurrent(generation, enabled: true) else {
                    return
                }
                if success {
                    self.snapshot.errorMessage = nil
                    self.startStatusPolling(generation: generation)
                    self.requestStatus(generation: generation)
                } else {
                    self.snapshot.status = .error
                    self.snapshot.errorMessage = errorMessage ?? "battery.control.applyFailed".localized
                    self.log.error("Battery helper rejected configuration")
                }
            }
        }
    }

    private func handleConfigureTransportFailure(operationID: UUID, message: String) {
        guard let operation = activeConfigureOperation,
              operation.id == operationID,
              finishConfigureOperation(operationID) else {
            return
        }
        connection?.invalidate()
        connection = nil
        guard isCurrent(operation.generation, enabled: true) else { return }
        snapshot.status = .error
        snapshot.errorMessage = message
        scheduleConfigureRetry(generation: operation.generation)
    }

    private func finishConfigureOperation(_ operationID: UUID) -> Bool {
        guard activeConfigureOperation?.id == operationID else { return false }
        configureTimeoutTask?.cancel()
        activeConfigureOperation = nil
        return true
    }

    private func clearActiveConfigureOperation() {
        configureTimeoutTask?.cancel()
        activeConfigureOperation = nil
    }
}

private extension BatteryChargeControlManager {
    func prepareHelperForReset(
        remainingAttempts: Int,
        generation: Int,
        revertOnFailure: Bool,
        completion: (@MainActor (Bool) -> Void)?
    ) -> Bool {
        switch helperStatus {
        case .notRegistered, .notFound:
            guard helperMayBeControlling else {
                clearLocalState()
                completion?(true)
                return false
            }
            do {
                try registerHelper()
                resetAndUnregister(
                    remainingAttempts: remainingAttempts,
                    generation: generation,
                    revertOnFailure: revertOnFailure,
                    completion: completion
                )
            } catch {
                finishDisableFailure(
                    error.localizedDescription,
                    generation: generation,
                    revertOnFailure: revertOnFailure,
                    completion: completion
                )
            }
            return false
        case .requiresApproval:
            guard helperMayBeControlling else {
                unregisterAfterReset(
                    remainingAttempts: 3,
                    generation: generation,
                    completion: completion
                )
                return false
            }
            openApprovalSettings()
            finishDisableFailure(
                "battery.control.approvalRequired".localized,
                generation: generation,
                revertOnFailure: revertOnFailure,
                completion: completion
            )
            return false
        case .enabled:
            return true
        @unknown default:
            finishDisableFailure(
                "battery.control.helperUnavailable".localized,
                generation: generation,
                revertOnFailure: revertOnFailure,
                completion: completion
            )
            return false
        }
    }

    func resetAndUnregister(
        remainingAttempts: Int,
        generation: Int,
        revertOnFailure: Bool,
        completion: (@MainActor (Bool) -> Void)?
    ) {
        guard isCurrent(generation, enabled: false) else {
            completion?(false)
            return
        }
        disableRetryTask?.cancel()
        helperStatus = helperService.status
        guard prepareHelperForReset(
            remainingAttempts: remainingAttempts,
            generation: generation,
            revertOnFailure: revertOnFailure,
            completion: completion
        ) else {
            return
        }

        guard let proxy = remoteProxy() else {
            retryDisable(
                "battery.control.helperUnavailable".localized,
                remainingAttempts: remainingAttempts,
                generation: generation,
                revertOnFailure: revertOnFailure,
                completion: completion
            )
            return
        }

        let operation = ResetOperation(
            id: UUID(),
            generation: generation,
            remainingAttempts: remainingAttempts,
            revertOnFailure: revertOnFailure,
            completion: completion
        )
        activeResetOperation = operation
        resetTimeoutTask?.cancel()
        resetTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
            self?.handleResetTransportFailure(
                operationID: operation.id,
                message: "battery.control.helperUnavailable".localized
            )
        }

        proxy.reset(revision: nextRequestRevision()) { [weak self] success, errorMessage in
            Task { @MainActor in
                guard let self,
                      self.finishResetOperation(operation.id),
                      self.isCurrent(generation, enabled: false) else {
                    return
                }
                guard success else {
                    self.retryDisable(
                        errorMessage ?? "battery.control.resetFailed".localized,
                        remainingAttempts: remainingAttempts,
                        generation: generation,
                        revertOnFailure: revertOnFailure,
                        completion: completion
                    )
                    return
                }
                self.helperMayBeControlling = false
                self.unregisterAfterReset(
                    remainingAttempts: 3,
                    generation: generation,
                    completion: completion
                )
            }
        }
    }

    private func handleResetTransportFailure(operationID: UUID, message: String) {
        guard let operation = activeResetOperation,
              operation.id == operationID,
              finishResetOperation(operationID) else {
            return
        }
        connection?.invalidate()
        connection = nil
        guard isCurrent(operation.generation, enabled: false) else {
            operation.completion?(false)
            return
        }
        retryDisable(
            message,
            remainingAttempts: operation.remainingAttempts,
            generation: operation.generation,
            revertOnFailure: operation.revertOnFailure,
            completion: operation.completion
        )
    }

    private func finishResetOperation(_ operationID: UUID) -> Bool {
        guard activeResetOperation?.id == operationID else { return false }
        resetTimeoutTask?.cancel()
        activeResetOperation = nil
        return true
    }

    private func unregisterAfterReset(
        remainingAttempts: Int,
        generation: Int,
        completion: (@MainActor (Bool) -> Void)?
    ) {
        guard isCurrent(generation, enabled: false) else {
            completion?(false)
            return
        }
        do {
            let service = helperService
            if service.status != .notRegistered, service.status != .notFound {
                try service.unregister()
            }
            helperStatus = helperService.status
            clearLocalState()
            completion?(true)
        } catch {
            let message = error.localizedDescription
            snapshot.status = .error
            snapshot.errorMessage = message
            log.error("Battery helper unregister failed: \(message)")
            guard remainingAttempts > 0 else {
                completion?(false)
                return
            }
            disableRetryTask?.cancel()
            disableRetryTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                self?.unregisterAfterReset(
                    remainingAttempts: remainingAttempts - 1,
                    generation: generation,
                    completion: completion
                )
            }
        }
    }

    private func retryDisable(
        _ message: String,
        remainingAttempts: Int,
        generation: Int,
        revertOnFailure: Bool,
        completion: (@MainActor (Bool) -> Void)?
    ) {
        snapshot.status = .error
        snapshot.errorMessage = message
        log.error("Battery helper disable failed: \(message)")
        guard remainingAttempts > 0 else {
            finishDisableFailure(
                message,
                generation: generation,
                revertOnFailure: revertOnFailure,
                completion: completion
            )
            return
        }
        disableRetryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }
            guard let self, self.isCurrent(generation, enabled: false) else { return }
            self.resetAndUnregister(
                remainingAttempts: remainingAttempts - 1,
                generation: generation,
                revertOnFailure: revertOnFailure,
                completion: completion
            )
        }
    }

    private func finishDisableFailure(
        _ message: String,
        generation: Int,
        revertOnFailure: Bool,
        completion: (@MainActor (Bool) -> Void)?
    ) {
        guard isCurrent(generation, enabled: false) else {
            completion?(false)
            return
        }
        snapshot.status = .error
        snapshot.errorMessage = message
        log.error("Battery helper disable failed: \(message)")
        if revertOnFailure {
            revertDisableToggle()
        }
        completion?(false)
    }

    private func revertDisableToggle() {
        controlEnabled = true
        guard !SettingsManager.shared.batteryChargeControlEnabled else { return }
        SettingsManager.shared.batteryChargeControlEnabled = true
    }

    private func clearLocalState() {
        stopStatusPolling()
        configureRetryTask?.cancel()
        configureTimeoutTask?.cancel()
        resetTimeoutTask?.cancel()
        activeConfigureOperation = nil
        activeResetOperation = nil
        connection?.invalidate()
        connection = nil
        snapshot = .inactive
        snapshot.upperLimit = desiredUpperLimit
        snapshot.lowerLimit = desiredLowerLimit
    }

    private func requestStatus(generation: Int) {
        guard isCurrent(generation, enabled: true), let proxy = remoteProxy() else { return }
        proxy.status { [weak self] status, backend, percent, upper, lower, supported, errorMessage in
            Task { @MainActor in
                guard let self, self.isCurrent(generation, enabled: true) else { return }
                self.snapshot.status = BatteryChargeControlStatus(rawValue: status) ?? .error
                self.snapshot.backend = BatteryChargeControlBackend(rawValue: backend) ?? .unknown
                self.snapshot.percent = percent >= 0 ? percent : nil
                self.snapshot.upperLimit = upper
                self.snapshot.lowerLimit = lower
                self.snapshot.helperAvailable = supported
                self.snapshot.errorMessage = errorMessage
            }
        }
    }

    private func startStatusPolling(generation: Int) {
        stopStatusPolling()
        statusTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    return
                }
                guard let self, self.isCurrent(generation, enabled: true) else { return }
                self.requestStatus(generation: generation)
            }
        }
    }

    private func stopStatusPolling() {
        statusTask?.cancel()
        statusTask = nil
    }

    private func scheduleConfigureRetry(generation: Int) {
        configureRetryTask?.cancel()
        configureRetryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }
            guard let self, self.isCurrent(generation, enabled: true) else { return }
            self.configureHelper(generation: generation)
        }
    }

    private func remoteProxy() -> BatteryControlHelperProtocol? {
        if connection == nil {
            let newConnection = NSXPCConnection(
                machServiceName: BatteryControlIPC.machServiceName,
                options: .privileged
            )
            newConnection.remoteObjectInterface = NSXPCInterface(
                with: BatteryControlHelperProtocol.self
            )
            newConnection.setCodeSigningRequirement(BatteryControlIPC.helperCodeSigningRequirement)
            newConnection.invalidationHandler = { [weak self, weak newConnection] in
                guard let newConnection else { return }
                Task { @MainActor in self?.connectionDidEnd(newConnection) }
            }
            newConnection.interruptionHandler = { [weak self, weak newConnection] in
                guard let newConnection else { return }
                Task { @MainActor in self?.connectionDidEnd(newConnection) }
            }
            newConnection.resume()
            connection = newConnection
        }

        guard let connection else { return nil }
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self, weak connection] error in
            guard let connection else { return }
            Task { @MainActor in
                self?.log.error("Battery helper connection failed: \(error.localizedDescription)")
                self?.connectionDidEnd(connection)
            }
        }
        return proxy as? BatteryControlHelperProtocol
    }

    private func connectionDidEnd(_ endedConnection: NSXPCConnection) {
        guard connection === endedConnection else { return }
        connection = nil
        if let operation = activeResetOperation {
            handleResetTransportFailure(
                operationID: operation.id,
                message: "battery.control.helperUnavailable".localized
            )
            return
        }
        if let operation = activeConfigureOperation {
            handleConfigureTransportFailure(
                operationID: operation.id,
                message: "battery.control.helperUnavailable".localized
            )
            return
        }
        guard controlEnabled else { return }
        snapshot.status = .error
        snapshot.errorMessage = "battery.control.helperUnavailable".localized
    }

    private func openApprovalSettings() {
        guard !didOpenApprovalSettings else { return }
        didOpenApprovalSettings = true
        SMAppService.openSystemSettingsLoginItems()
    }

    private func isCurrent(_ generation: Int, enabled: Bool) -> Bool {
        generation == transitionGeneration && controlEnabled == enabled
    }

    private func nextRequestRevision() -> Int64 {
        requestRevision += 1
        return requestRevision
    }

    private var helperMayBeControlling: Bool {
        get { SettingsManager.shared.batteryChargeHelperMayBeControlling }
        set { SettingsManager.shared.batteryChargeHelperMayBeControlling = newValue }
    }

    private var helperService: SMAppService {
        SMAppService.daemon(plistName: BatteryControlIPC.daemonPlistName)
    }
}

private enum BatteryControlManagerError: LocalizedError {
    case requiresApproval
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Battery helper requires approval"
        case .registrationFailed:
            return "Battery helper registration failed"
        }
    }
}
