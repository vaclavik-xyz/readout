import Foundation

struct OutputQueueSnapshot: Sendable {
    let name: String
    let queued: Int
    let enqueued: Int
    let processed: Int
    let dropped: Int
    let failed: Int
    let retried: Int
}

actor OutputWriteQueue {
    typealias Operation = @Sendable () async throws -> Void
    typealias HealthHandler = @Sendable (RuntimeLogLevel, String) -> Void

    private struct QueuedOperation: Sendable {
        let operation: Operation
        var attempt: Int
    }

    private let name: String
    private let capacity: Int
    private let maxRetryAttempts: Int
    private let baseRetryDelaySeconds: TimeInterval
    private let maxRetryDelaySeconds: TimeInterval
    private let onHealth: HealthHandler

    private var queue: [QueuedOperation] = []
    private var workerTask: Task<Void, Never>?

    private var enqueuedCount = 0
    private var processedCount = 0
    private var droppedCount = 0
    private var failedCount = 0
    private var retriedCount = 0
    private var consecutiveFailures = 0

    private var lastProcessedSnapshot = 0
    private let snapshotEveryProcessed = 200

    init(
        name: String,
        capacity: Int,
        maxRetryAttempts: Int,
        baseRetryDelaySeconds: TimeInterval = 0.05,
        maxRetryDelaySeconds: TimeInterval = 1.0,
        onHealth: @escaping HealthHandler
    ) {
        self.name = name
        self.capacity = max(4, capacity)
        self.maxRetryAttempts = max(0, maxRetryAttempts)
        self.baseRetryDelaySeconds = max(0.001, baseRetryDelaySeconds)
        self.maxRetryDelaySeconds = max(self.baseRetryDelaySeconds, maxRetryDelaySeconds)
        self.onHealth = onHealth
    }

    func enqueue(_ operation: @escaping Operation) {
        enqueuedCount += 1

        if queue.count >= capacity {
            queue.removeFirst()
            droppedCount += 1
            if droppedCount == 1 || droppedCount.isMultiple(of: 25) {
                onHealth(
                    .warning,
                    "Output queue \(name): dropped \(droppedCount) writes (capacity \(capacity), queued \(queue.count))."
                )
            }
        }

        queue.append(QueuedOperation(operation: operation, attempt: 0))

        if workerTask == nil {
            workerTask = Task {
                await self.runWorkerLoop()
            }
        }
    }

    func shutdown(flush: Bool) async {
        if !flush {
            queue.removeAll(keepingCapacity: false)
        }

        if flush && workerTask == nil && !queue.isEmpty {
            workerTask = Task {
                await self.runWorkerLoop()
            }
        }

        while flush && (!queue.isEmpty || workerTask != nil) {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        workerTask?.cancel()
        _ = await workerTask?.result
        workerTask = nil
    }

    func snapshot() -> OutputQueueSnapshot {
        OutputQueueSnapshot(
            name: name,
            queued: queue.count,
            enqueued: enqueuedCount,
            processed: processedCount,
            dropped: droppedCount,
            failed: failedCount,
            retried: retriedCount
        )
    }

    private func runWorkerLoop() async {
        defer {
            workerTask = nil
        }

        while !Task.isCancelled {
            guard var next = queue.first else {
                break
            }
            queue.removeFirst()

            do {
                try await next.operation()
                processedCount += 1

                if consecutiveFailures > 0 {
                    onHealth(.info, "Output queue \(name): recovered after \(consecutiveFailures) consecutive failures.")
                    consecutiveFailures = 0
                }
                emitPeriodicSnapshotIfNeeded()
            } catch {
                failedCount += 1
                consecutiveFailures += 1

                if next.attempt < maxRetryAttempts {
                    next.attempt += 1
                    retriedCount += 1
                    queue.insert(next, at: 0)

                    let delay = retryDelaySeconds(forAttempt: next.attempt)
                    onHealth(
                        .warning,
                        "Output queue \(name): write failed, retry \(next.attempt)/\(maxRetryAttempts) in \(String(format: "%.2f", delay))s (\(error.localizedDescription))."
                    )
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    droppedCount += 1
                    onHealth(
                        .warning,
                        "Output queue \(name): dropped write after \(maxRetryAttempts) retries (\(error.localizedDescription))."
                    )
                }
            }
        }
    }

    private func emitPeriodicSnapshotIfNeeded() {
        guard processedCount - lastProcessedSnapshot >= snapshotEveryProcessed else {
            return
        }
        lastProcessedSnapshot = processedCount

        onHealth(
            .info,
            "Output queue \(name): processed \(processedCount), dropped \(droppedCount), retried \(retriedCount), queued \(queue.count)."
        )
    }

    private func retryDelaySeconds(forAttempt attempt: Int) -> TimeInterval {
        let power = max(0, attempt - 1)
        let exponential = baseRetryDelaySeconds * pow(2.0, Double(power))
        let capped = min(maxRetryDelaySeconds, exponential)
        let jitter = Double.random(in: 0.85...1.15)
        return max(0.001, capped * jitter)
    }
}
