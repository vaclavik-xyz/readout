import Foundation
import Testing
@testable import ReadOutMacApp

private actor IntRecorder {
    private var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }

    func snapshot() -> [Int] {
        values
    }
}

private actor HealthRecorder {
    private var entries: [(RuntimeLogLevel, String)] = []

    func append(level: RuntimeLogLevel, message: String) {
        entries.append((level, message))
    }

    func containsMessage(_ needle: String) -> Bool {
        entries.contains(where: { $0.1.contains(needle) })
    }
}

private actor AttemptCounter {
    private var count: Int = 0

    func increment() -> Int {
        count += 1
        return count
    }

    func snapshot() -> Int {
        count
    }
}

@Test
func queueDropsOldestWritesWhenCapacityIsExceeded() async throws {
    let executed = IntRecorder()
    let health = HealthRecorder()

    let queue = OutputWriteQueue(
        name: "test-overflow",
        capacity: 2,
        maxRetryAttempts: 0
    ) { level, message in
        Task {
            await health.append(level: level, message: message)
        }
    }

    for index in 0..<6 {
        await queue.enqueue {
            await executed.append(index)
            try await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    try await Task.sleep(nanoseconds: 500_000_000)
    await queue.shutdown(flush: true)

    let snapshot = await queue.snapshot()
    let executedValues = await executed.snapshot()
    #expect(snapshot.dropped > 0)
    #expect(snapshot.enqueued == 6)
    #expect(snapshot.processed == executedValues.count)
    #expect(snapshot.processed + snapshot.dropped == snapshot.enqueued)
    #expect(executedValues.contains(5))
    #expect(await health.containsMessage("dropped"))
}

@Test
func queueRetriesAndRecoversAfterTransientFailure() async throws {
    let health = HealthRecorder()
    let counter = AttemptCounter()

    let queue = OutputWriteQueue(
        name: "test-retry",
        capacity: 8,
        maxRetryAttempts: 3,
        baseRetryDelaySeconds: 0.01,
        maxRetryDelaySeconds: 0.02
    ) { level, message in
        Task {
            await health.append(level: level, message: message)
        }
    }

    await queue.enqueue {
        let attempt = await counter.increment()
        if attempt < 3 {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    try await Task.sleep(nanoseconds: 400_000_000)
    await queue.shutdown(flush: true)

    let snapshot = await queue.snapshot()
    #expect(await counter.snapshot() == 3)
    #expect(snapshot.processed == 1)
    #expect(snapshot.retried == 2)
    #expect(snapshot.failed == 2)
    #expect(snapshot.dropped == 0)
    #expect(await health.containsMessage("recovered after 2 consecutive failures"))
}
