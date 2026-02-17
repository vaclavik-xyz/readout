import Foundation
import Testing
@testable import ReadOutIO

private struct MockError: Error, LocalizedError, Equatable, Sendable {
    let message: String
    var errorDescription: String? { message }
}

private actor EventRecorder {
    private var _events: [DeviceSessionEvent] = []

    func append(_ event: DeviceSessionEvent) {
        _events.append(event)
    }

    func events() -> [DeviceSessionEvent] {
        _events
    }
}

private actor MockSleeper: DeviceSessionSleeper {
    private(set) var calls: [TimeInterval] = []

    func sleep(seconds: TimeInterval) async {
        calls.append(seconds)
    }

    func recordedCalls() -> [TimeInterval] {
        calls
    }
}

private actor MockTransport: DeviceTransport {
    enum ReadOutcome: Sendable {
        case frame(String)
        case endStream
        case fail(String)
        case pause(seconds: TimeInterval)
    }

    private var openOutcomes: [Result<Void, MockError>]
    private var readOutcomes: [ReadOutcome]
    private(set) var openCallCount = 0
    private(set) var closeCallCount = 0

    init(openOutcomes: [Result<Void, MockError>], readOutcomes: [ReadOutcome]) {
        self.openOutcomes = openOutcomes
        self.readOutcomes = readOutcomes
    }

    func open() async throws {
        openCallCount += 1
        if openOutcomes.isEmpty {
            return
        }
        let outcome = openOutcomes.removeFirst()
        switch outcome {
        case .success:
            return
        case let .failure(error):
            throw error
        }
    }

    func close() async {
        closeCallCount += 1
    }

    func readFrame() async throws -> String? {
        guard !readOutcomes.isEmpty else {
            return nil
        }

        let next = readOutcomes.removeFirst()
        switch next {
        case let .frame(value):
            return value
        case .endStream:
            return nil
        case let .fail(message):
            throw MockError(message: message)
        case let .pause(seconds):
            let nanos = UInt64(max(0, seconds) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanos)
            return nil
        }
    }

    func counters() -> (open: Int, close: Int) {
        (openCallCount, closeCallCount)
    }
}

private func waitUntil(
    timeoutSeconds: TimeInterval = 1.0,
    pollIntervalSeconds: TimeInterval = 0.01,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if await condition() {
            return true
        }
        let nanos = UInt64(max(0, pollIntervalSeconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }
    return false
}

private func almostEqual(_ lhs: TimeInterval, _ rhs: TimeInterval, epsilon: TimeInterval = 0.000_001) -> Bool {
    abs(lhs - rhs) <= epsilon
}

@Test
func reconnectPolicyDelayBackoffIsCapped() {
    let policy = ReconnectPolicy(
        enabled: true,
        initialDelaySeconds: 0.1,
        maxDelaySeconds: 0.25,
        multiplier: 2
    )

    #expect(policy.delay(forAttempt: 0) == 0)
    #expect(almostEqual(policy.delay(forAttempt: 1), 0.1))
    #expect(almostEqual(policy.delay(forAttempt: 2), 0.2))
    #expect(almostEqual(policy.delay(forAttempt: 3), 0.25))
    #expect(almostEqual(policy.delay(forAttempt: 4), 0.25))
}

@Test
func sessionReadsFramesWithoutReconnect() async {
    let recorder = EventRecorder()
    let transport = MockTransport(
        openOutcomes: [.success(())],
        readOutcomes: [.frame("A"), .frame("B"), .endStream]
    )

    let config = DeviceSessionConfiguration(
        reconnectPolicy: ReconnectPolicy(enabled: false)
    )

    let session = DeviceSession(
        id: "multimeter",
        transport: transport,
        configuration: config
    ) { event in
        Task { await recorder.append(event) }
    }

    await session.start()
    let disconnected = await waitUntil {
        await session.currentState() == .disconnected
    }

    #expect(disconnected == true)

    let events = await recorder.events()
    #expect(events.contains(.frameReceived("A")))
    #expect(events.contains(.frameReceived("B")))
    #expect(events.contains(.stateChanged(.connected)))
    #expect(events.contains(where: {
        if case .transportError = $0 { return true }
        return false
    }))

    await session.stop()
}

@Test
func sessionReconnectsAfterOpenFailure() async {
    let recorder = EventRecorder()
    let sleeper = MockSleeper()
    let transport = MockTransport(
        openOutcomes: [
            .failure(MockError(message: "initial connect failed")),
            .success(())
        ],
        readOutcomes: [
            .frame("RECOVERED"),
            .endStream
        ]
    )

    let config = DeviceSessionConfiguration(
        reconnectPolicy: ReconnectPolicy(
            enabled: true,
            initialDelaySeconds: 0,
            maxDelaySeconds: 0,
            multiplier: 1
        )
    )

    let session = DeviceSession(
        id: "usbc",
        transport: transport,
        configuration: config,
        sleeper: sleeper
    ) { event in
        Task { await recorder.append(event) }
    }

    await session.start()
    let recovered = await waitUntil(timeoutSeconds: 2.0) {
        await recorder.events().contains(.frameReceived("RECOVERED"))
    }
    #expect(recovered == true)

    await session.stop()
    #expect(await session.currentState() == .disconnected)

    let counters = await transport.counters()
    #expect(counters.open >= 2)

    let sleepCalls = await sleeper.recordedCalls()
    #expect(sleepCalls.isEmpty == false)
    #expect(sleepCalls.allSatisfy { $0 == 0 })

    let events = await recorder.events()
    #expect(events.contains(.stateChanged(.reconnecting(attempt: 1))))
    #expect(events.contains(.stateChanged(.waitingRetry(attempt: 1, delaySeconds: 0))))
    #expect(events.contains(.frameReceived("RECOVERED")))
}

@Test
func stopTransitionsSessionToDisconnected() async {
    let recorder = EventRecorder()
    let transport = MockTransport(
        openOutcomes: [.success(())],
        readOutcomes: [.pause(seconds: 10)]
    )

    let session = DeviceSession(
        id: "stop-test",
        transport: transport
    ) { event in
        Task { await recorder.append(event) }
    }

    await session.start()
    let connected = await waitUntil {
        await session.currentState() == .connected
    }
    #expect(connected == true)

    await session.stop()
    #expect(await session.currentState() == .disconnected)

    let counters = await transport.counters()
    #expect(counters.close >= 1)

    let disconnected = await waitUntil {
        await session.currentState() == .disconnected
    }
    #expect(disconnected == true)
}

@Test
func sessionAppliesBackoffAcrossRepeatedOpenFailures() async {
    let recorder = EventRecorder()
    let sleeper = MockSleeper()
    let transport = MockTransport(
        openOutcomes: [
            .failure(MockError(message: "open-fail-1")),
            .failure(MockError(message: "open-fail-2")),
            .failure(MockError(message: "open-fail-3")),
            .success(())
        ],
        readOutcomes: [
            .pause(seconds: 10)
        ]
    )

    let config = DeviceSessionConfiguration(
        reconnectPolicy: ReconnectPolicy(
            enabled: true,
            initialDelaySeconds: 0.1,
            maxDelaySeconds: 0.25,
            multiplier: 2
        )
    )

    let session = DeviceSession(
        id: "backoff-test",
        transport: transport,
        configuration: config,
        sleeper: sleeper
    ) { event in
        Task { await recorder.append(event) }
    }

    await session.start()
    let reachedThirdRetry = await waitUntil(timeoutSeconds: 2.0) {
        await recorder.events().contains(.stateChanged(.waitingRetry(attempt: 3, delaySeconds: 0.25)))
    }
    #expect(reachedThirdRetry == true)

    await session.stop()

    let sleepCalls = await sleeper.recordedCalls()
    #expect(sleepCalls.count >= 3)
    #expect(almostEqual(sleepCalls[0], 0.1))
    #expect(almostEqual(sleepCalls[1], 0.2))
    #expect(almostEqual(sleepCalls[2], 0.25))

    let events = await recorder.events()
    #expect(events.contains(where: {
        if case .transportError(let message) = $0 {
            return message.contains("open-fail-1")
                || message.contains("open-fail-2")
                || message.contains("open-fail-3")
        }
        return false
    }))
}
