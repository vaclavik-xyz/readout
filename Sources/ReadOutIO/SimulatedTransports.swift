import Foundation

public enum SimulatedPort {
    public static let multimeter = "SIM_MULTIMETER"
    public static let usbC = "SIM_USBC"
}

public enum SimulatedTransportError: Error {
    case notOpen
}

public actor SimulatedSCPITransport: SCPITransport {
    private let sampleIntervalSeconds: TimeInterval

    private var isOpen = false
    private var sampleIndex: Int = 0
    private var beeperEnabled = false

    public init(sampleRateHz: Int = 10) {
        let hz = max(1, sampleRateHz)
        sampleIntervalSeconds = 1.0 / Double(hz)
    }

    public func open() async throws {
        isOpen = true
        sampleIndex = 0
    }

    public func close() async {
        isOpen = false
    }

    public func readFrame() async throws -> String? {
        guard isOpen else {
            throw SimulatedTransportError.notOpen
        }

        await sleep(seconds: sampleIntervalSeconds)

        let mode = currentMode(for: sampleIndex)
        let value = measurementString(for: mode, sampleIndex: sampleIndex)
        sampleIndex += 1
        return value
    }

    public func query(_ command: String) async throws -> String? {
        guard isOpen else {
            throw SimulatedTransportError.notOpen
        }

        let normalized = command
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized {
        case "FUNC?":
            return currentMode(for: sampleIndex)

        case "SYST:BEEP:STAT ON":
            beeperEnabled = true
            return "OK"

        case "SYST:BEEP:STAT OFF":
            beeperEnabled = false
            return "OK"

        case "SYST:BEEP:STAT?":
            return beeperEnabled ? "1" : "0"

        case "*IDN?":
            return "SIMULATED,READOUT,MULTIMETER,1.0"

        case "MEAS?", "MEAS1:SHOW?":
            let mode = currentMode(for: sampleIndex)
            let value = measurementString(for: mode, sampleIndex: sampleIndex)
            sampleIndex += 1
            return value

        default:
            return nil
        }
    }

    private func currentMode(for index: Int) -> String {
        switch (index / 220) % 4 {
        case 0: return "VOLT:DC"
        case 1: return "CURR:DC"
        case 2: return "RES"
        default: return "VOLT:AC"
        }
    }

    private func measurementString(for mode: String, sampleIndex: Int) -> String {
        let t = Double(sampleIndex) * sampleIntervalSeconds

        switch mode {
        case "VOLT:DC":
            let v = 12.0 + 0.25 * sin(t * 1.2)
            return String(format: "%.4f", v)

        case "CURR:DC":
            let a = 1.4 + 0.3 * sin(t * 1.8 + 0.5)
            return String(format: "%.5f", a)

        case "RES":
            if sampleIndex % 160 == 0 {
                return "OL"
            }
            let ohm = 120.0 + 45.0 * sin(t * 0.8)
            return String(format: "%.3f", ohm)

        case "VOLT:AC":
            let vac = 230.0 + 8.0 * sin(t * 0.6)
            return String(format: "%.3f", vac)

        default:
            return "0"
        }
    }
}

public actor SimulatedStreamingTransport: DeviceTransport {
    private let sampleIntervalSeconds: TimeInterval

    private var isOpen = false
    private var sampleIndex: Int = 0

    public init(sampleRateHz: Int = 10) {
        let hz = max(1, sampleRateHz)
        sampleIntervalSeconds = 1.0 / Double(hz)
    }

    public func open() async throws {
        isOpen = true
        sampleIndex = 0
    }

    public func close() async {
        isOpen = false
    }

    public func readFrame() async throws -> String? {
        guard isOpen else {
            throw SimulatedTransportError.notOpen
        }

        await sleep(seconds: sampleIntervalSeconds)

        let t = Double(sampleIndex) * sampleIntervalSeconds
        sampleIndex += 1

        let voltage = max(3.3, min(20.0, 9.0 + 1.8 * sin(t * 0.65)))
        let current = max(0.0, min(4.5, 1.3 + 0.45 * sin(t * 1.05 + 0.7)))

        return encodeUsbCFrame(voltage: voltage, current: current)
    }

    private func encodeUsbCFrame(voltage: Double, current: Double) -> String {
        let busRaw = Int(round(voltage / 0.003125)).clamped(to: 0...65535)

        let shuntSigned = Int(round(current / 0.0002)).clamped(to: -32768...32767)
        let shuntRaw: Int
        if shuntSigned < 0 {
            shuntRaw = 65536 + shuntSigned
        } else {
            shuntRaw = shuntSigned
        }

        return String(format: "%04X%04X", shuntRaw, busRaw)
    }
}

private func sleep(seconds: TimeInterval) async {
    let clamped = max(0, seconds)
    let nanos = UInt64(clamped * 1_000_000_000)
    try? await Task.sleep(nanoseconds: nanos)
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
