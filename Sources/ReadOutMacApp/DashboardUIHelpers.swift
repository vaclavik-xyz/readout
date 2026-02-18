import SwiftUI
import ReadOutCore

enum DashboardUIHelpers {
    static func alarmMarkerColor(_ state: MeasurementAlertState) -> Color {
        switch state {
        case .none:
            return .gray
        case .short:
            return .orange
        case .open:
            return .pink
        case .highAlarm:
            return .red
        case .lowAlarm:
            return .yellow
        }
    }

    static func alarmMarkerLabel(_ state: MeasurementAlertState) -> String {
        switch state {
        case .none:
            return "NONE"
        case .short:
            return "SHORT"
        case .open:
            return "OPEN"
        case .highAlarm:
            return "HIGH"
        case .lowAlarm:
            return "LOW"
        }
    }

    static func connectionOverlayColor(_ state: ConnectionOverlayState) -> Color {
        switch state {
        case .reconnecting:
            return .cyan
        case .error:
            return .red
        case .restored:
            return .green
        }
    }

    static func connectionOverlayLabel(_ state: ConnectionOverlayState) -> String {
        switch state {
        case .reconnecting:
            return "RETRY"
        case .error:
            return "ERROR"
        case .restored:
            return "RESTORED"
        }
    }

    static func logLevelColor(_ level: RuntimeLogLevel) -> Color {
        switch level {
        case .info:
            return .mint
        case .warning:
            return .yellow
        case .error:
            return .red
        }
    }

    static func runtimeHealthColor(_ severity: RuntimeHealthSeverity) -> Color {
        switch severity {
        case .good:
            return .mint
        case .warning:
            return .yellow
        case .critical:
            return .red
        }
    }

    static func alertAccentColor(_ alertState: MeasurementAlertState?, defaultColor: Color) -> Color {
        guard let alertState else {
            return defaultColor
        }

        switch alertState {
        case .none:
            return defaultColor
        case .short:
            return .orange
        case .open:
            return .pink
        case .highAlarm:
            return .red
        case .lowAlarm:
            return .yellow
        }
    }
}
