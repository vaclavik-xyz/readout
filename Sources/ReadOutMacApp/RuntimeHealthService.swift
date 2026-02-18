import Foundation
import ReadOutCore

@MainActor
final class RuntimeHealthService: ObservableObject {
    struct OutputQueueHealthState {
        var queued: Int = 0
        var dropped: Int = 0
        var retried: Int = 0
        var processed: Int = 0
    }

    struct UIRefreshMetrics {
        let appliedHz: Double
        let skippedHz: Double
        let smoothedProcessingMs: Double
        let isRenderPaused: Bool
        let isRuntimeActive: Bool
        let mode: String
        let targetHz: Int
    }

    struct HealthSnapshotContext {
        let isRuntimeActive: Bool
        let multimeterStatus: DeviceUIState
        let usbcStatus: DeviceUIState
        let runtimeLogCount: Int
        let statusMessage: String
    }

    @Published private(set) var runtimeHealthBadges: [RuntimeHealthBadge] = []

    private(set) var reconnectCount = 0
    private(set) var runtimeErrorCount = 0
    private(set) var parseErrorCount = 0
    private(set) var outputDropWarningCount = 0

    private var healthSnapshots: [RuntimeHealthSnapshot] = []
    private var outputQueueHealthByName: [String: OutputQueueHealthState] = [:]

    func refreshBadges(
        uiMetrics: UIRefreshMetrics,
        outputQueueCapacity: Int,
        logCount: Int,
        isLogCaptureEnabled: Bool
    ) {
        let targetHz = Double(uiMetrics.targetHz)
        let uiSeverity: RuntimeHealthSeverity
        if uiMetrics.isRenderPaused {
            uiSeverity = .warning
        } else if uiMetrics.isRuntimeActive, uiMetrics.appliedHz < targetHz * 0.5 {
            uiSeverity = .critical
        } else if uiMetrics.isRuntimeActive, uiMetrics.appliedHz < targetHz * 0.8 || uiMetrics.skippedHz > 1.0 || uiMetrics.mode == "high-load" {
            uiSeverity = .warning
        } else {
            uiSeverity = .good
        }

        let queueStates = outputQueueHealthByName.values
        let queueDropped = queueStates.reduce(0) { $0 + $1.dropped }
        let queueRetried = queueStates.reduce(0) { $0 + $1.retried }
        let queueProcessed = queueStates.reduce(0) { $0 + $1.processed }
        let queueMaxDepth = queueStates.map(\.queued).max() ?? 0
        let queueDepthWarning = max(1, Int(Double(outputQueueCapacity) * 0.6))
        let queueDepthCritical = max(1, Int(Double(outputQueueCapacity) * 0.9))

        let queueSeverity: RuntimeHealthSeverity
        if queueDropped > 0 || queueMaxDepth >= queueDepthCritical {
            queueSeverity = .critical
        } else if queueRetried > 0 || queueMaxDepth >= queueDepthWarning {
            queueSeverity = .warning
        } else {
            queueSeverity = .good
        }

        let runtimeIssueCount = runtimeErrorCount + parseErrorCount + outputDropWarningCount
        let runtimeSeverity: RuntimeHealthSeverity
        if runtimeErrorCount > 0 || outputDropWarningCount > 0 {
            runtimeSeverity = .critical
        } else if parseErrorCount > 0 || reconnectCount > 0 {
            runtimeSeverity = .warning
        } else {
            runtimeSeverity = .good
        }

        let queueValue: String
        if queueStates.isEmpty {
            queueValue = "waiting for queue stats"
        } else {
            queueValue = "maxQ \(queueMaxDepth)/\(outputQueueCapacity) | drop \(queueDropped) | retry \(queueRetried) | ok \(queueProcessed)"
        }

        runtimeHealthBadges = [
            RuntimeHealthBadge(
                id: "ui_refresh",
                title: "UI Refresh",
                value: String(
                    format: "%.1f/%.0fHz | skip %.1fHz | %.1fms",
                    uiMetrics.appliedHz,
                    targetHz,
                    uiMetrics.skippedHz,
                    uiMetrics.smoothedProcessingMs
                ),
                severity: uiSeverity
            ),
            RuntimeHealthBadge(
                id: "output_queues",
                title: "Output Queues",
                value: queueValue,
                severity: queueSeverity
            ),
            RuntimeHealthBadge(
                id: "runtime_faults",
                title: "Runtime Faults",
                value: "err \(runtimeErrorCount) | parse \(parseErrorCount) | reconnect \(reconnectCount) | warnings \(runtimeIssueCount)",
                severity: runtimeSeverity
            ),
            RuntimeHealthBadge(
                id: "log_capture",
                title: "Log Capture",
                value: isLogCaptureEnabled
                    ? "INFO/WARN/ERR (\(logCount) entries)"
                    : "WARN/ERR only (\(logCount) entries)",
                severity: isLogCaptureEnabled ? .good : .warning
            )
        ]
    }

    func recordRuntimeLogHealth(level: RuntimeLogLevel, message: String) {
        let lowered = message.lowercased()
        if lowered.contains("output queue"), lowered.contains("dropped"), level == .warning {
            outputDropWarningCount += 1
        }
        if lowered.contains("parse"), (level == .warning || level == .error) {
            parseErrorCount += 1
        }
        updateOutputQueueHealth(message: message)
    }

    func incrementReconnectCount() {
        reconnectCount += 1
    }

    func incrementRuntimeErrorCount() {
        runtimeErrorCount += 1
    }

    func incrementParseErrorCount() {
        parseErrorCount += 1
    }

    func appendHealthSnapshot(reason: String, context: HealthSnapshotContext) {
        healthSnapshots.append(
            RuntimeHealthSnapshot(
                timestamp: Date(),
                reason: reason,
                isRuntimeActive: context.isRuntimeActive,
                multimeterStatus: context.multimeterStatus,
                usbcStatus: context.usbcStatus,
                reconnectCount: reconnectCount,
                runtimeErrorCount: runtimeErrorCount,
                parseErrorCount: parseErrorCount,
                outputDropWarningCount: outputDropWarningCount,
                runtimeLogCount: context.runtimeLogCount,
                statusMessage: context.statusMessage
            )
        )
        if healthSnapshots.count > 500 {
            healthSnapshots.removeFirst(healthSnapshots.count - 500)
        }
    }

    func diagnosticSnapshots() -> [RuntimeHealthSnapshot] {
        Array(healthSnapshots.suffix(500))
    }

    private func updateOutputQueueHealth(message: String) {
        guard message.hasPrefix("Output queue ") else {
            return
        }

        let prefixCount = "Output queue ".count
        guard message.count > prefixCount else {
            return
        }
        let prefixStart = message.index(message.startIndex, offsetBy: prefixCount)
        guard let separator = message[prefixStart...].firstIndex(of: ":") else {
            return
        }

        let name = String(message[prefixStart..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }

        let bodyStart = message.index(after: separator)
        let body = String(message[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyLower = body.lowercased()
        var state = outputQueueHealthByName[name] ?? OutputQueueHealthState()

        if let processed = integerValue(after: "processed ", in: body) {
            state.processed = max(state.processed, processed)
        }
        if let dropped = integerValue(after: "dropped ", in: body),
           bodyLower.contains("writes") || bodyLower.contains("retried") || bodyLower.contains("queued") {
            state.dropped = max(state.dropped, dropped)
        }
        if let retried = integerValue(after: "retried ", in: body) {
            state.retried = max(state.retried, retried)
        }
        if let queued = integerValue(after: "queued ", in: body) {
            state.queued = queued
        }
        if bodyLower.contains("write failed, retry") {
            state.retried += 1
        }
        if bodyLower.contains("dropped write after") {
            state.dropped += 1
        }

        outputQueueHealthByName[name] = state
    }

    private func integerValue(after token: String, in text: String) -> Int? {
        guard let tokenRange = text.range(of: token) else {
            return nil
        }

        var cursor = tokenRange.upperBound
        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }

        let digitsStart = cursor
        while cursor < text.endIndex, text[cursor].isNumber {
            cursor = text.index(after: cursor)
        }

        guard digitsStart < cursor else {
            return nil
        }
        return Int(text[digitsStart..<cursor])
    }
}
