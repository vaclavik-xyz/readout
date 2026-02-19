import Foundation
import Testing
@testable import ReadOutMacApp

@MainActor
@Suite
struct RuntimeHealthServiceTests {
    private func defaultUIMetrics(
        appliedHz: Double = 10.0,
        skippedHz: Double = 0.0,
        smoothedProcessingMs: Double = 1.0,
        isRenderPaused: Bool = false,
        isRuntimeActive: Bool = true,
        mode: String = "normal",
        targetHz: Int = 10
    ) -> RuntimeHealthService.UIRefreshMetrics {
        RuntimeHealthService.UIRefreshMetrics(
            appliedHz: appliedHz,
            skippedHz: skippedHz,
            smoothedProcessingMs: smoothedProcessingMs,
            isRenderPaused: isRenderPaused,
            isRuntimeActive: isRuntimeActive,
            mode: mode,
            targetHz: targetHz
        )
    }

    private func badge(id: String, in badges: [RuntimeHealthBadge]) -> RuntimeHealthBadge? {
        badges.first(where: { $0.id == id })
    }

    @Test
    func initialBadgesAreAllGood() {
        let service = RuntimeHealthService()

        service.refreshBadges(
            uiMetrics: defaultUIMetrics(),
            outputQueueCapacity: 100,
            logCount: 0,
            isLogCaptureEnabled: true
        )

        let badges = service.runtimeHealthBadges
        #expect(badge(id: "ui_refresh", in: badges)?.severity == .good)
        #expect(badge(id: "runtime_faults", in: badges)?.severity == .good)
        #expect(badge(id: "log_capture", in: badges)?.severity == .good)
    }

    @Test
    func runtimeErrorIncrementMarksCritical() {
        let service = RuntimeHealthService()

        service.incrementRuntimeErrorCount()
        service.refreshBadges(
            uiMetrics: defaultUIMetrics(),
            outputQueueCapacity: 100,
            logCount: 0,
            isLogCaptureEnabled: true
        )

        #expect(badge(id: "runtime_faults", in: service.runtimeHealthBadges)?.severity == .critical)
    }

    @Test
    func parseErrorMarksWarning() {
        let service = RuntimeHealthService()

        service.incrementParseErrorCount()
        service.refreshBadges(
            uiMetrics: defaultUIMetrics(),
            outputQueueCapacity: 100,
            logCount: 0,
            isLogCaptureEnabled: true
        )

        #expect(badge(id: "runtime_faults", in: service.runtimeHealthBadges)?.severity == .warning)
    }

    @Test
    func reconnectCountMarksWarning() {
        let service = RuntimeHealthService()

        service.incrementReconnectCount()
        service.refreshBadges(
            uiMetrics: defaultUIMetrics(),
            outputQueueCapacity: 100,
            logCount: 0,
            isLogCaptureEnabled: true
        )

        #expect(badge(id: "runtime_faults", in: service.runtimeHealthBadges)?.severity == .warning)
    }

    @Test
    func outputQueueDropDetection() {
        let service = RuntimeHealthService()

        service.recordRuntimeLogHealth(
            level: .warning,
            message: "Output queue CSV: dropped 3 writes"
        )
        service.refreshBadges(
            uiMetrics: defaultUIMetrics(),
            outputQueueCapacity: 100,
            logCount: 0,
            isLogCaptureEnabled: true
        )

        #expect(badge(id: "output_queues", in: service.runtimeHealthBadges)?.severity == .critical)
    }

    @Test
    func outputQueueRetryDetection() {
        let service = RuntimeHealthService()

        service.recordRuntimeLogHealth(
            level: .info,
            message: "Output queue CSV: write failed, retry"
        )
        service.refreshBadges(
            uiMetrics: defaultUIMetrics(),
            outputQueueCapacity: 100,
            logCount: 0,
            isLogCaptureEnabled: true
        )

        #expect(badge(id: "output_queues", in: service.runtimeHealthBadges)?.severity == .warning)
    }

    @Test
    func renderPausedShowsUiWarning() {
        let service = RuntimeHealthService()

        service.refreshBadges(
            uiMetrics: defaultUIMetrics(isRenderPaused: true),
            outputQueueCapacity: 100,
            logCount: 0,
            isLogCaptureEnabled: true
        )

        #expect(badge(id: "ui_refresh", in: service.runtimeHealthBadges)?.severity == .warning)
    }

    @Test
    func healthSnapshotAppendAndCap() {
        let service = RuntimeHealthService()
        let context = RuntimeHealthService.HealthSnapshotContext(
            isRuntimeActive: true,
            multimeterStatus: .connected,
            usbcStatus: .disconnected,
            runtimeLogCount: 0,
            statusMessage: "OK"
        )

        for i in 0..<501 {
            service.appendHealthSnapshot(reason: "tick-\(i)", context: context)
        }

        #expect(service.diagnosticSnapshots().count == 500)
    }

    @Test
    func logCaptureDisabledShowsWarning() {
        let service = RuntimeHealthService()

        service.refreshBadges(
            uiMetrics: defaultUIMetrics(),
            outputQueueCapacity: 100,
            logCount: 5,
            isLogCaptureEnabled: false
        )

        #expect(badge(id: "log_capture", in: service.runtimeHealthBadges)?.severity == .warning)
    }
}
