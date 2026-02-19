import Foundation
import Testing
@testable import ReadOutMacApp
import ReadOutCore

@MainActor
@Suite
struct AlarmControlServiceTests {
    private func makeService() -> AlarmControlService {
        AlarmControlService(beepController: PcBeepController())
    }

    @Test
    func toggleAcknowledgeSetsAndClears() {
        let service = makeService()

        _ = service.toggleAcknowledge(latestAlertState: .highAlarm)
        #expect(service.isAlarmAcknowledged)

        _ = service.toggleAcknowledge(latestAlertState: .highAlarm)
        #expect(!service.isAlarmAcknowledged)
    }

    @Test
    func silenceExpiresAfterDuration() async throws {
        let service = makeService()

        _ = service.silenceAlarms(for: 0.1, latestAlertState: .none)
        #expect(service.isAlarmSilenced)

        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        service.refreshState(latestAlertState: .none, now: Date(), emitStatusOnExpiry: false)
        #expect(!service.isAlarmSilenced)
    }

    @Test
    func clearSilenceRemovesSilence() {
        let service = makeService()

        _ = service.silenceAlarms(for: 60, latestAlertState: .none)
        #expect(service.isAlarmSilenced)

        _ = service.clearSilence(latestAlertState: .none)
        #expect(!service.isAlarmSilenced)
    }

    @Test
    func reconcileAcknowledgeClearsOnStateChange() {
        let service = makeService()

        _ = service.toggleAcknowledge(latestAlertState: .highAlarm)
        #expect(service.isAlarmAcknowledged)

        service.reconcileAcknowledge(previousAlert: .highAlarm, currentAlert: .short)
        #expect(!service.isAlarmAcknowledged)
    }

    @Test
    func reconcileAcknowledgeClearsOnNone() {
        let service = makeService()

        _ = service.toggleAcknowledge(latestAlertState: .highAlarm)
        #expect(service.isAlarmAcknowledged)

        service.reconcileAcknowledge(previousAlert: .highAlarm, currentAlert: .none)
        #expect(!service.isAlarmAcknowledged)
    }

    @Test
    func alarmControlSummaryFormat() {
        let service = makeService()

        _ = service.toggleAcknowledge(latestAlertState: .highAlarm)
        _ = service.silenceAlarms(for: 60, latestAlertState: .highAlarm)

        let summary = service.alarmControlSummary
        #expect(summary.contains("Acked"))
        #expect(summary.contains("Silenced"))
    }

    @Test
    func resetStateClearsAcknowledge() {
        let service = makeService()

        _ = service.toggleAcknowledge(latestAlertState: .highAlarm)
        #expect(service.isAlarmAcknowledged)

        service.resetState()

        #expect(!service.isAlarmAcknowledged)
    }

    @Test
    func resetStateLeavesActiveSilenceIntact() {
        let service = makeService()

        _ = service.silenceAlarms(for: 60, latestAlertState: .highAlarm)

        service.resetState()

        // resetState does not clear alarmSilencedUntil; active silence persists
        #expect(service.isAlarmSilenced)
    }

    @Test
    func resetStateWithNoSilenceShowsLive() {
        let service = makeService()

        _ = service.toggleAcknowledge(latestAlertState: .highAlarm)

        service.resetState()

        #expect(service.alarmControlSummary == "Live")
    }
}
