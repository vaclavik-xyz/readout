import Foundation

public struct EnergySnapshot: Equatable, Sendable {
    public let powerWatts: Double
    public let energyMWh: Double
    public let energyMAh: Double

    public init(powerWatts: Double, energyMWh: Double, energyMAh: Double) {
        self.powerWatts = powerWatts
        self.energyMWh = energyMWh
        self.energyMAh = energyMAh
    }
}

public struct EnergyAccumulator: Sendable {
    public private(set) var energyMWh: Double = 0
    public private(set) var energyMAh: Double = 0
    public private(set) var lastMeasurementAt: Date?

    public init() {}

    public mutating func reset() {
        energyMWh = 0
        energyMAh = 0
        lastMeasurementAt = nil
    }

    public mutating func update(voltage: Double, current: Double, at timestamp: Date = Date()) -> EnergySnapshot {
        let power = abs(voltage * current)
        if let previous = lastMeasurementAt {
            let deltaHours = timestamp.timeIntervalSince(previous) / 3600.0
            energyMWh += power * 1000 * deltaHours
            energyMAh += current * 1000 * deltaHours
        }
        lastMeasurementAt = timestamp
        return EnergySnapshot(powerWatts: power, energyMWh: energyMWh, energyMAh: energyMAh)
    }
}
