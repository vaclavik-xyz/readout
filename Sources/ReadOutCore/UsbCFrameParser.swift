import Foundation

public struct UsbCFrameMeasurement: Equatable, Sendable {
    public let voltage: Double
    public let current: Double

    public init(voltage: Double, current: Double) {
        self.voltage = voltage
        self.current = current
    }
}

public enum UsbCFrameParser {
    public static let voltageQuantum = 0.003125
    public static let currentQuantum = 0.0002
    public static let frameLength = 8

    public static func isValidFrame(_ rawFrame: String) -> Bool {
        let frame = rawFrame.trimmingCharacters(in: .whitespacesAndNewlines)
        guard frame.count == frameLength else {
            return false
        }
        return Int(frame, radix: 16) != nil
    }

    public static func parse(_ rawFrame: String) -> UsbCFrameMeasurement? {
        let frame = rawFrame.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidFrame(frame) else {
            return nil
        }

        let shuntHex = String(frame.prefix(4))
        let busHex = String(frame.suffix(4))

        guard var shuntRaw = Int(shuntHex, radix: 16),
              let busRaw = Int(busHex, radix: 16) else {
            return nil
        }

        if shuntRaw > 32767 {
            shuntRaw -= 65536
        }

        let voltage = Double(busRaw) * voltageQuantum
        var current = Double(shuntRaw) * currentQuantum
        if current < 0 {
            current = 0
        }

        return UsbCFrameMeasurement(voltage: voltage, current: current)
    }
}
