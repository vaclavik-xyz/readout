public enum MeasurementMode: Equatable, Sendable {
    case dcVoltage
    case acVoltage
    case resistance
    case continuity
    case diode
    case dcCurrent
    case acCurrent
    case capacitance
    case frequency
    case period
    case temperature
    case unknown
}

public enum MeasurementModeParser {
    // Mirrors legacy Python behavior from enums.parse_mode_from_string.
    public static func parse(_ modeString: String?) -> MeasurementMode {
        guard let raw = modeString?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .unknown
        }

        if raw.contains("VOLT") {
            return raw.contains("AC") ? .acVoltage : .dcVoltage
        }
        if raw.contains("CURR") {
            return raw.contains("AC") ? .acCurrent : .dcCurrent
        }
        if raw.contains("CONT") {
            return .continuity
        }
        if raw.contains("RES") || raw.contains("OHM") || raw.contains("FRES") {
            return .resistance
        }
        if raw.contains("DIOD") {
            return .diode
        }
        if raw.contains("CAP") {
            return .capacitance
        }
        if raw.contains("FREQ") {
            return .frequency
        }
        if raw.contains("PER") {
            return .period
        }
        if raw.contains("TEMP") {
            return .temperature
        }

        return .unknown
    }
}
