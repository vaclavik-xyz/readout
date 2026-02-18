import Foundation
import ReadOutCore
import ReadOutPersistence

@MainActor
final class AlarmControlService: ObservableObject {
    @Published private(set) var isAlarmAcknowledged: Bool = false
    @Published private(set) var isAlarmSilenced: Bool = false
    @Published private(set) var alarmSilenceRemainingText: String = ""
    @Published private(set) var alarmControlSummary: String = "Live"

    private var acknowledgedAlertState: MeasurementAlertState = .none
    private var alarmSilencedUntil: Date?
    private let beepController: PcBeepController

    init(beepController: PcBeepController) {
        self.beepController = beepController
    }

    func toggleAcknowledge(latestAlertState: MeasurementAlertState) -> String {
        let message: String
        if isAlarmAcknowledged {
            isAlarmAcknowledged = false
            acknowledgedAlertState = .none
            message = "Alarm acknowledge cleared"
        } else {
            isAlarmAcknowledged = true
            acknowledgedAlertState = latestAlertState
            message = "Alarm acknowledged (\(DashboardAlertService.text(for: latestAlertState)))"
        }
        refreshState(latestAlertState: latestAlertState, now: Date(), emitStatusOnExpiry: false)
        return message
    }

    @discardableResult
    func silenceAlarms(
        for seconds: TimeInterval,
        latestAlertState: MeasurementAlertState
    ) -> String {
        let clamped = max(0.1, seconds)
        alarmSilencedUntil = Date().addingTimeInterval(clamped)
        refreshState(latestAlertState: latestAlertState, now: Date(), emitStatusOnExpiry: false)
        return "Alarms silenced for \(formatSilenceDuration(clamped))"
    }

    @discardableResult
    func silenceAlarms(
        using preset: AlarmSilencePreset,
        latestAlertState: MeasurementAlertState
    ) -> String {
        silenceAlarms(for: preset.seconds, latestAlertState: latestAlertState)
    }

    func clearSilence(latestAlertState: MeasurementAlertState) -> String? {
        guard alarmSilencedUntil != nil || isAlarmSilenced else {
            return nil
        }
        alarmSilencedUntil = nil
        refreshState(latestAlertState: latestAlertState, now: Date(), emitStatusOnExpiry: false)
        return "Alarm silence cleared"
    }

    struct RefreshResult {
        var expiryStatusMessage: String?
        var silenceDidExpire: Bool = false
    }

    @discardableResult
    func refreshState(
        latestAlertState: MeasurementAlertState,
        now: Date,
        emitStatusOnExpiry: Bool
    ) -> RefreshResult {
        let wasSilenced = isAlarmSilenced
        var result = RefreshResult()

        if let until = alarmSilencedUntil {
            if now >= until {
                alarmSilencedUntil = nil
                isAlarmSilenced = false
                alarmSilenceRemainingText = ""
                result.silenceDidExpire = true
                if emitStatusOnExpiry && wasSilenced {
                    result.expiryStatusMessage = "Alarm silence expired"
                }
            } else {
                isAlarmSilenced = true
                alarmSilenceRemainingText = formatRemainingSilence(until.timeIntervalSince(now))
            }
        } else {
            isAlarmSilenced = false
            alarmSilenceRemainingText = ""
        }

        if isAlarmAcknowledged,
           latestAlertState == .none || acknowledgedAlertState != latestAlertState {
            isAlarmAcknowledged = false
            acknowledgedAlertState = .none
        }

        let ackText = isAlarmAcknowledged
            ? "Acked \(DashboardAlertService.text(for: acknowledgedAlertState))"
            : nil
        let silenceText = isAlarmSilenced
            ? "Silenced \(alarmSilenceRemainingText)"
            : nil
        alarmControlSummary = [ackText, silenceText]
            .compactMap { $0 }
            .joined(separator: " | ")
        if alarmControlSummary.isEmpty {
            alarmControlSummary = "Live"
        }

        return result
    }

    func reconcileAcknowledge(
        previousAlert: MeasurementAlertState,
        currentAlert: MeasurementAlertState
    ) {
        guard previousAlert != currentAlert else {
            return
        }

        if currentAlert == .none {
            isAlarmAcknowledged = false
            acknowledgedAlertState = .none
            return
        }

        if isAlarmAcknowledged, acknowledgedAlertState != currentAlert {
            isAlarmAcknowledged = false
            acknowledgedAlertState = .none
        }
    }

    func updateBeep(
        for alert: MeasurementAlertState,
        configuration: AppConfiguration,
        isDashboardBeepEnabled: Bool
    ) {
        let isAcknowledgedForAlert = isAlarmAcknowledged
            && acknowledgedAlertState == alert
            && alert != .none
        let shouldBeep = DashboardAlertService.shouldBeep(
            for: alert,
            configuration: configuration,
            dashboardBeepMasterEnabled: isDashboardBeepEnabled,
            alarmMuted: isAlarmSilenced || isAcknowledgedForAlert
        )
        beepController.setBeeping(shouldBeep)
    }

    func configureBeep(soundPreset: MacAlertSoundPreset, volume: Double) {
        beepController.configure(soundPreset: soundPreset, volume: volume)
    }

    func stopBeep() {
        beepController.setBeeping(false)
    }

    func resetState() {
        acknowledgedAlertState = .none
        isAlarmAcknowledged = false
        refreshState(latestAlertState: .none, now: Date(), emitStatusOnExpiry: false)
    }

    private func formatRemainingSilence(_ seconds: TimeInterval) -> String {
        let rounded = max(0, Int(seconds.rounded(.up)))
        let minutes = rounded / 60
        let remainingSeconds = rounded % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func formatSilenceDuration(_ seconds: TimeInterval) -> String {
        let rounded = max(1, Int(seconds.rounded()))
        let minutes = rounded / 60
        let remainingSeconds = rounded % 60
        if minutes == 0 {
            return "\(remainingSeconds)s"
        }
        if remainingSeconds == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(remainingSeconds)s"
    }
}
