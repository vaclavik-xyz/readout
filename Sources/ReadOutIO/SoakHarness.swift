import Foundation

public struct SoakFaultProfile: Sendable, Equatable, Codable {
    public var seed: UInt64
    public var openFailureProbability: Double
    public var disconnectProbabilityPerRead: Double
    public var readFailureProbabilityPerRead: Double
    public var slowReadProbabilityPerRead: Double
    public var slowReadDelaySeconds: TimeInterval

    public init(
        seed: UInt64,
        openFailureProbability: Double,
        disconnectProbabilityPerRead: Double,
        readFailureProbabilityPerRead: Double,
        slowReadProbabilityPerRead: Double,
        slowReadDelaySeconds: TimeInterval
    ) {
        self.seed = seed
        self.openFailureProbability = Self.clampedProbability(openFailureProbability)
        self.disconnectProbabilityPerRead = Self.clampedProbability(disconnectProbabilityPerRead)
        self.readFailureProbabilityPerRead = Self.clampedProbability(readFailureProbabilityPerRead)
        self.slowReadProbabilityPerRead = Self.clampedProbability(slowReadProbabilityPerRead)
        self.slowReadDelaySeconds = max(0, slowReadDelaySeconds)
    }

    private static func clampedProbability(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public struct SoakThresholds: Sendable, Equatable, Codable {
    public var maxTransportErrors: Int
    public var maxReconnectAttempts: Int
    public var minFramesCaptured: Int

    public init(
        maxTransportErrors: Int,
        maxReconnectAttempts: Int,
        minFramesCaptured: Int
    ) {
        self.maxTransportErrors = max(0, maxTransportErrors)
        self.maxReconnectAttempts = max(0, maxReconnectAttempts)
        self.minFramesCaptured = max(0, minFramesCaptured)
    }
}

public struct SoakRunConfiguration: Sendable, Equatable {
    public var sessionID: String
    public var sampleRateHz: Int
    public var targetFrames: Int
    public var timeoutSeconds: TimeInterval
    public var reconnectPolicy: ReconnectPolicy
    public var faultProfile: SoakFaultProfile
    public var thresholds: SoakThresholds

    public init(
        sessionID: String,
        sampleRateHz: Int,
        targetFrames: Int,
        timeoutSeconds: TimeInterval,
        reconnectPolicy: ReconnectPolicy,
        faultProfile: SoakFaultProfile,
        thresholds: SoakThresholds
    ) {
        self.sessionID = sessionID
        self.sampleRateHz = max(1, sampleRateHz)
        self.targetFrames = max(1, targetFrames)
        self.timeoutSeconds = max(1, timeoutSeconds)
        self.reconnectPolicy = reconnectPolicy
        self.faultProfile = faultProfile
        self.thresholds = thresholds
    }
}

public struct SoakTransportFaultCounters: Sendable, Equatable, Codable {
    public let openFailuresInjected: Int
    public let disconnectsInjected: Int
    public let readFailuresInjected: Int
    public let slowReadsInjected: Int
}

public struct SoakRunSummary: Sendable, Equatable, Codable {
    public let startedAt: Date
    public let finishedAt: Date
    public let elapsedSeconds: Double
    public let seed: UInt64
    public let sampleRateHz: Int
    public let targetFrames: Int
    public let framesCaptured: Int
    public let reachedTargetFrames: Bool
    public let reconnectAttempts: Int
    public let waitingRetryEvents: Int
    public let transportErrors: Int
    public let transportFaults: SoakTransportFaultCounters
    public let thresholdFailures: [String]
    public let passed: Bool
}

public enum SoakPreset: String, CaseIterable, Sendable {
    case smoke = "smoke"
    case p30m = "30m"
    case p2h = "2h"
    case p24h = "24h"

    public func configuration(seed: UInt64) -> SoakRunConfiguration {
        switch self {
        case .smoke:
            return SoakRunConfiguration(
                sessionID: "soak-smoke",
                sampleRateHz: 120,
                targetFrames: 400,
                timeoutSeconds: 12,
                reconnectPolicy: ReconnectPolicy(enabled: true, initialDelaySeconds: 0.05, maxDelaySeconds: 0.4, multiplier: 2),
                faultProfile: SoakFaultProfile(
                    seed: seed,
                    openFailureProbability: 0.03,
                    disconnectProbabilityPerRead: 0.01,
                    readFailureProbabilityPerRead: 0.015,
                    slowReadProbabilityPerRead: 0.02,
                    slowReadDelaySeconds: 0.03
                ),
                thresholds: SoakThresholds(
                    maxTransportErrors: 80,
                    maxReconnectAttempts: 80,
                    minFramesCaptured: 400
                )
            )

        case .p30m:
            return SoakRunConfiguration(
                sessionID: "soak-30m",
                sampleRateHz: 10,
                targetFrames: 18_000,
                timeoutSeconds: 2_100,
                reconnectPolicy: ReconnectPolicy(enabled: true, initialDelaySeconds: 0.15, maxDelaySeconds: 2.0, multiplier: 1.8),
                faultProfile: SoakFaultProfile(
                    seed: seed,
                    openFailureProbability: 0.002,
                    disconnectProbabilityPerRead: 0.0005,
                    readFailureProbabilityPerRead: 0.001,
                    slowReadProbabilityPerRead: 0.003,
                    slowReadDelaySeconds: 0.06
                ),
                thresholds: SoakThresholds(
                    maxTransportErrors: 250,
                    maxReconnectAttempts: 250,
                    minFramesCaptured: 17_500
                )
            )

        case .p2h:
            return SoakRunConfiguration(
                sessionID: "soak-2h",
                sampleRateHz: 10,
                targetFrames: 72_000,
                timeoutSeconds: 8_200,
                reconnectPolicy: ReconnectPolicy(enabled: true, initialDelaySeconds: 0.2, maxDelaySeconds: 3.0, multiplier: 1.8),
                faultProfile: SoakFaultProfile(
                    seed: seed,
                    openFailureProbability: 0.001,
                    disconnectProbabilityPerRead: 0.0003,
                    readFailureProbabilityPerRead: 0.0007,
                    slowReadProbabilityPerRead: 0.002,
                    slowReadDelaySeconds: 0.07
                ),
                thresholds: SoakThresholds(
                    maxTransportErrors: 700,
                    maxReconnectAttempts: 700,
                    minFramesCaptured: 70_000
                )
            )

        case .p24h:
            return SoakRunConfiguration(
                sessionID: "soak-24h",
                sampleRateHz: 10,
                targetFrames: 864_000,
                timeoutSeconds: 92_000,
                reconnectPolicy: ReconnectPolicy(enabled: true, initialDelaySeconds: 0.2, maxDelaySeconds: 4.0, multiplier: 1.8),
                faultProfile: SoakFaultProfile(
                    seed: seed,
                    openFailureProbability: 0.0006,
                    disconnectProbabilityPerRead: 0.00015,
                    readFailureProbabilityPerRead: 0.0004,
                    slowReadProbabilityPerRead: 0.0015,
                    slowReadDelaySeconds: 0.08
                ),
                thresholds: SoakThresholds(
                    maxTransportErrors: 5_500,
                    maxReconnectAttempts: 5_500,
                    minFramesCaptured: 850_000
                )
            )
        }
    }
}

public enum SoakRunner {
    public static func runStreamingSimulation(configuration: SoakRunConfiguration) async -> SoakRunSummary {
        let startedAt = Date()
        let recorder = SoakEventRecorder()
        let base = SimulatedStreamingTransport(sampleRateHz: configuration.sampleRateHz)
        let faultingTransport = FaultInjectingTransport(
            transport: base,
            profile: configuration.faultProfile
        )

        let session = DeviceSession(
            id: configuration.sessionID,
            transport: faultingTransport,
            configuration: DeviceSessionConfiguration(reconnectPolicy: configuration.reconnectPolicy)
        ) { event in
            Task {
                await recorder.record(event)
            }
        }

        await session.start()

        let reachedTarget = await waitUntil(
            timeoutSeconds: configuration.timeoutSeconds,
            condition: {
                await recorder.framesCaptured() >= configuration.targetFrames
            }
        )

        await session.stop()

        let metrics = await recorder.snapshot()
        let transportFaults = await faultingTransport.faultCounters()
        let finishedAt = Date()
        let elapsed = finishedAt.timeIntervalSince(startedAt)
        let failures = evaluateThresholds(
            thresholds: configuration.thresholds,
            metrics: metrics
        )

        return SoakRunSummary(
            startedAt: startedAt,
            finishedAt: finishedAt,
            elapsedSeconds: elapsed,
            seed: configuration.faultProfile.seed,
            sampleRateHz: configuration.sampleRateHz,
            targetFrames: configuration.targetFrames,
            framesCaptured: metrics.framesCaptured,
            reachedTargetFrames: reachedTarget,
            reconnectAttempts: metrics.reconnectAttempts,
            waitingRetryEvents: metrics.waitingRetryEvents,
            transportErrors: metrics.transportErrors,
            transportFaults: transportFaults,
            thresholdFailures: failures,
            passed: reachedTarget && failures.isEmpty
        )
    }

    private static func evaluateThresholds(
        thresholds: SoakThresholds,
        metrics: SoakEventMetrics
    ) -> [String] {
        var failures: [String] = []
        if metrics.transportErrors > thresholds.maxTransportErrors {
            failures.append("transport_errors_exceeded")
        }
        if metrics.reconnectAttempts > thresholds.maxReconnectAttempts {
            failures.append("reconnect_attempts_exceeded")
        }
        if metrics.framesCaptured < thresholds.minFramesCaptured {
            failures.append("insufficient_frames_captured")
        }
        return failures
    }
}

private actor SoakEventRecorder {
    private var frames = 0
    private var reconnectAttempts = 0
    private var waitingRetryEvents = 0
    private var transportErrors = 0

    func record(_ event: DeviceSessionEvent) {
        switch event {
        case .frameReceived:
            frames += 1
        case .transportError:
            transportErrors += 1
        case .stateChanged(let state):
            switch state {
            case .reconnecting:
                reconnectAttempts += 1
            case .waitingRetry:
                waitingRetryEvents += 1
            default:
                break
            }
        }
    }

    func framesCaptured() -> Int {
        frames
    }

    func snapshot() -> SoakEventMetrics {
        SoakEventMetrics(
            framesCaptured: frames,
            reconnectAttempts: reconnectAttempts,
            waitingRetryEvents: waitingRetryEvents,
            transportErrors: transportErrors
        )
    }
}

private struct SoakEventMetrics: Sendable {
    let framesCaptured: Int
    let reconnectAttempts: Int
    let waitingRetryEvents: Int
    let transportErrors: Int
}

private actor FaultInjectingTransport: DeviceTransport {
    private enum InjectedError: Error, LocalizedError {
        case openFailed
        case disconnected
        case readFailed

        var errorDescription: String? {
            switch self {
            case .openFailed:
                return "Injected open failure"
            case .disconnected:
                return "Injected disconnect"
            case .readFailed:
                return "Injected read failure"
            }
        }
    }

    private let transport: any DeviceTransport
    private let profile: SoakFaultProfile
    private var rng: SeededRandom

    private var openFailuresInjected = 0
    private var disconnectsInjected = 0
    private var readFailuresInjected = 0
    private var slowReadsInjected = 0

    init(
        transport: any DeviceTransport,
        profile: SoakFaultProfile
    ) {
        self.transport = transport
        self.profile = profile
        self.rng = SeededRandom(seed: profile.seed)
    }

    func open() async throws {
        if shouldInject(profile.openFailureProbability) {
            openFailuresInjected += 1
            throw InjectedError.openFailed
        }
        try await transport.open()
    }

    func close() async {
        await transport.close()
    }

    func readFrame() async throws -> String? {
        if shouldInject(profile.slowReadProbabilityPerRead) {
            slowReadsInjected += 1
            try? await Task.sleep(nanoseconds: UInt64(profile.slowReadDelaySeconds * 1_000_000_000))
        }

        if shouldInject(profile.disconnectProbabilityPerRead) {
            disconnectsInjected += 1
            await transport.close()
            throw InjectedError.disconnected
        }

        if shouldInject(profile.readFailureProbabilityPerRead) {
            readFailuresInjected += 1
            throw InjectedError.readFailed
        }

        return try await transport.readFrame()
    }

    func faultCounters() -> SoakTransportFaultCounters {
        SoakTransportFaultCounters(
            openFailuresInjected: openFailuresInjected,
            disconnectsInjected: disconnectsInjected,
            readFailuresInjected: readFailuresInjected,
            slowReadsInjected: slowReadsInjected
        )
    }

    private func shouldInject(_ probability: Double) -> Bool {
        rng.nextUnitInterval() < probability
    }
}

private struct SeededRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnitInterval() -> Double {
        Double(next()) / Double(UInt64.max)
    }
}

private func waitUntil(
    timeoutSeconds: TimeInterval,
    pollIntervalSeconds: TimeInterval = 0.02,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let timeout = max(0.01, timeoutSeconds)
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: UInt64(max(0.001, pollIntervalSeconds) * 1_000_000_000))
    }

    return false
}
