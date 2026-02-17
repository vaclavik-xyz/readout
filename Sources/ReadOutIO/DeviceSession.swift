import Foundation

public protocol DeviceTransport: Sendable {
    func open() async throws
    func close() async
    func readFrame() async throws -> String?
}

public protocol DeviceSessionSleeper: Sendable {
    func sleep(seconds: TimeInterval) async
}

public struct TaskSleeper: DeviceSessionSleeper {
    public init() {}

    public func sleep(seconds: TimeInterval) async {
        let clamped = max(0, seconds)
        let nanos = UInt64(clamped * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }
}

public struct ReconnectPolicy: Sendable, Equatable {
    public var enabled: Bool
    public var initialDelaySeconds: TimeInterval
    public var maxDelaySeconds: TimeInterval
    public var multiplier: Double

    public init(
        enabled: Bool = true,
        initialDelaySeconds: TimeInterval = 0.5,
        maxDelaySeconds: TimeInterval = 5.0,
        multiplier: Double = 2.0
    ) {
        self.enabled = enabled
        self.initialDelaySeconds = initialDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
        self.multiplier = multiplier
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else {
            return 0
        }
        let raw = initialDelaySeconds * pow(multiplier, Double(attempt - 1))
        return min(maxDelaySeconds, raw)
    }
}

public struct DeviceSessionConfiguration: Sendable, Equatable {
    public var reconnectPolicy: ReconnectPolicy

    public init(reconnectPolicy: ReconnectPolicy = .init()) {
        self.reconnectPolicy = reconnectPolicy
    }
}

public enum DeviceSessionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case waitingRetry(attempt: Int, delaySeconds: TimeInterval)
    case stopping
    case disconnected
}

public enum DeviceSessionEvent: Equatable, Sendable {
    case stateChanged(DeviceSessionState)
    case frameReceived(String)
    case transportError(String)
}

public enum DeviceSessionInternalError: Error {
    case endOfStream
}

public actor DeviceSession {
    public let id: String

    private let transport: any DeviceTransport
    private let configuration: DeviceSessionConfiguration
    private let sleeper: any DeviceSessionSleeper
    private let onEvent: @Sendable (DeviceSessionEvent) -> Void

    private var state: DeviceSessionState = .idle
    private var loopTask: Task<Void, Never>?

    public init(
        id: String,
        transport: any DeviceTransport,
        configuration: DeviceSessionConfiguration = .init(),
        sleeper: any DeviceSessionSleeper = TaskSleeper(),
        onEvent: @escaping @Sendable (DeviceSessionEvent) -> Void = { _ in }
    ) {
        self.id = id
        self.transport = transport
        self.configuration = configuration
        self.sleeper = sleeper
        self.onEvent = onEvent
    }

    public func start() {
        guard loopTask == nil else {
            return
        }

        loopTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.runLoop()
        }
    }

    public func stop() async {
        transition(to: .stopping)

        loopTask?.cancel()
        await transport.close()
        loopTask = nil

        transition(to: .disconnected)
    }

    public func currentState() -> DeviceSessionState {
        state
    }

    private func runLoop() async {
        var reconnectAttempt = 0

        while !Task.isCancelled {
            if reconnectAttempt == 0 {
                transition(to: .connecting)
            } else {
                transition(to: .reconnecting(attempt: reconnectAttempt))
            }

            do {
                try await transport.open()
                transition(to: .connected)
                reconnectAttempt = 0

                while !Task.isCancelled {
                    guard let frame = try await transport.readFrame() else {
                        throw DeviceSessionInternalError.endOfStream
                    }
                    onEvent(.frameReceived(frame))
                }

            } catch is CancellationError {
                break
            } catch {
                let errorMessage = (error as NSError).localizedDescription
                onEvent(.transportError(errorMessage))
                await transport.close()

                if !configuration.reconnectPolicy.enabled || Task.isCancelled {
                    break
                }

                reconnectAttempt += 1
                let delay = configuration.reconnectPolicy.delay(forAttempt: reconnectAttempt)
                transition(to: .waitingRetry(attempt: reconnectAttempt, delaySeconds: delay))
                await sleeper.sleep(seconds: delay)
            }
        }

        await transport.close()
        transition(to: .disconnected)
        loopTask = nil
    }

    private func transition(to newState: DeviceSessionState) {
        guard state != newState else {
            return
        }
        state = newState
        onEvent(.stateChanged(newState))
    }
}
