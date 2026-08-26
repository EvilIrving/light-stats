import Foundation

final class BatteryControlXPC: NSObject, BatteryControlHelperProtocol {
    private let engine: BatteryControlEngine
    private let connectionGeneration: Int64

    init(engine: BatteryControlEngine, connectionGeneration: Int64) {
        self.engine = engine
        self.connectionGeneration = connectionGeneration
    }

    func configure(
        enabled: Bool,
        upperLimit: Int,
        lowerLimit: Int,
        revision: Int64,
        withReply reply: @escaping (Bool, String?) -> Void
    ) {
        Task { @MainActor [engine, connectionGeneration] in
            guard engine.acceptRequest(
                connectionGeneration: connectionGeneration,
                revision: revision
            ) else {
                reply(false, "Stale battery-control request")
                return
            }
            let result = engine.configure(
                enabled: enabled,
                upperLimit: upperLimit,
                lowerLimit: lowerLimit
            )
            reply(result.0, result.1)
        }
    }

    func status(
        withReply reply: @escaping (Int, Int, Int, Int, Int, Bool, String?) -> Void
    ) {
        Task { @MainActor [engine] in
            let result = engine.status()
            reply(result.0, result.1, result.2, result.3, result.4, result.5, result.6)
        }
    }

    func reset(revision: Int64, withReply reply: @escaping (Bool, String?) -> Void) {
        Task { @MainActor [engine, connectionGeneration] in
            guard engine.acceptRequest(
                connectionGeneration: connectionGeneration,
                revision: revision
            ) else {
                reply(false, "Stale battery-control request")
                return
            }
            let result = engine.reset()
            reply(result.0, result.1)
        }
    }
}

final class BatteryControlListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let engine: BatteryControlEngine
    private var nextConnectionGeneration: Int64 = 0

    init(engine: BatteryControlEngine) {
        self.engine = engine
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        nextConnectionGeneration += 1
        newConnection.exportedInterface = NSXPCInterface(with: BatteryControlHelperProtocol.self)
        newConnection.exportedObject = BatteryControlXPC(
            engine: engine,
            connectionGeneration: nextConnectionGeneration
        )
        newConnection.invalidationHandler = {}
        newConnection.interruptionHandler = {}
        newConnection.resume()
        return true
    }
}
