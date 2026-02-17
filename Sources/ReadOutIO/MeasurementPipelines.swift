import Foundation
import ReadOutCore

public actor MultimeterMeasurementPipeline {
    private var cachedModeString: String = ""
    private var modeRefreshCounter: Int = 0
    private let modeRefreshInterval: Int

    public init(modeRefreshInterval: Int = 10) {
        self.modeRefreshInterval = max(1, modeRefreshInterval)
    }

    // Mirrors legacy behavior: cache the mode and refresh periodically.
    public func shouldRefreshMode() -> Bool {
        modeRefreshCounter += 1
        if cachedModeString.isEmpty || modeRefreshCounter >= modeRefreshInterval {
            modeRefreshCounter = 0
            return true
        }
        return false
    }

    public func updateMode(_ modeString: String?) {
        cachedModeString = modeString?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public func decodeMeasurementResponse(_ response: String?, at timestamp: Date = Date()) -> DeviceMeasurement? {
        let modeString = cachedModeString
        guard let parsed = MultimeterParser.parse(response: response, modeString: modeString) else {
            return nil
        }

        return DeviceMeasurement(
            device: .multimeter,
            mode: parsed.mode,
            modeString: parsed.modeString,
            primaryValue: parsed.value,
            primaryUnit: parsed.unit,
            isOverload: parsed.isOverload,
            isOpen: parsed.isOpen,
            timestamp: timestamp
        )
    }
}

public actor UsbCMeasurementPipeline {
    private var energyAccumulator = EnergyAccumulator()

    public init() {}

    public func resetEnergy() {
        energyAccumulator.reset()
    }

    public func decodeFrame(_ frame: String, at timestamp: Date = Date()) -> DeviceMeasurement? {
        guard let parsed = UsbCFrameParser.parse(frame) else {
            return nil
        }

        let snapshot = energyAccumulator.update(
            voltage: parsed.voltage,
            current: parsed.current,
            at: timestamp
        )

        return DeviceMeasurement(
            device: .usbC,
            mode: .dcVoltage,
            modeString: "USB-C Power",
            primaryValue: parsed.voltage,
            primaryUnit: "V DC",
            secondaryValue: parsed.current,
            secondaryUnit: "A DC",
            powerWatts: snapshot.powerWatts,
            energyMWh: snapshot.energyMWh,
            energyMAh: snapshot.energyMAh,
            timestamp: timestamp
        )
    }
}
