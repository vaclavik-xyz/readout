import Foundation
import ReadOutCore
import ReadOutIO
import ReadOutPersistence

actor ReadOutRuntime {
    private let onEvent: @Sendable (RuntimeEvent) -> Void

    private var multimeterTask: Task<Void, Never>?
    private var usbcTask: Task<Void, Never>?

    init(onEvent: @escaping @Sendable (RuntimeEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start(with configuration: AppConfiguration) async {
        await stop()

        if configuration.multimeterEnabled {
            if !configuration.useSimulator && configuration.multimeterPort.isEmpty {
                onEvent(.multimeterStatus(.error, "Multimeter port is empty"))
            } else {
                multimeterTask = Task { [configuration, onEvent] in
                    await Self.runMultimeterLoop(configuration: configuration, onEvent: onEvent)
                }
            }
        } else {
            onEvent(.multimeterStatus(.disconnected, nil))
        }

        if configuration.usbcEnabled {
            if !configuration.useSimulator && configuration.usbcPort.isEmpty {
                onEvent(.usbcStatus(.error, "USB-C port is empty"))
            } else {
                usbcTask = Task { [configuration, onEvent] in
                    await Self.runUsbCLoop(configuration: configuration, onEvent: onEvent)
                }
            }
        } else {
            onEvent(.usbcStatus(.disconnected, nil))
        }
    }

    func stop() async {
        let mmTask = multimeterTask
        let ucTask = usbcTask

        multimeterTask = nil
        usbcTask = nil

        mmTask?.cancel()
        ucTask?.cancel()

        _ = await mmTask?.result
        _ = await ucTask?.result

        onEvent(.multimeterStatus(.disconnected, nil))
        onEvent(.usbcStatus(.disconnected, nil))
    }

    private static func runMultimeterLoop(
        configuration: AppConfiguration,
        onEvent: @escaping @Sendable (RuntimeEvent) -> Void
    ) async {
        let reconnectEnabled = configuration.multimeterAutoReconnect
        let sampleIntervalSeconds = 1.0 / Double(max(1, configuration.sampleRateHz))
        let alertConfiguration = configuration.alertConfiguration

        let csvLogger = CsvLogger()
        let obsWriter = ObsOutputWriter()
        var reconnectAttempt = 0

        while !Task.isCancelled {
            onEvent(.multimeterStatus(.connecting, nil))

            let transport: any SCPITransport
            if configuration.useSimulator {
                transport = SimulatedSCPITransport(sampleRateHz: configuration.sampleRateHz)
            } else {
                let lineIO = POSIXSerialPort(
                    configuration: SerialPortConfiguration(
                        path: configuration.multimeterPort,
                        baudRate: 115_200,
                        readTimeoutSeconds: 0.15,
                        writeTimeoutSeconds: 0.15
                    )
                )
                transport = SCPIPollingTransport(lineIO: lineIO)
            }
            let driver = MultimeterDeviceDriver(transport: transport)

            do {
                try await driver.connect()
                reconnectAttempt = 0
                let source = configuration.useSimulator ? "simulator" : configuration.multimeterPort
                onEvent(.multimeterStatus(.connected, "Multimeter connected (\(source))"))

                do {
                    _ = try await driver.setBeeperEnabled(configuration.beepOnShortMeter)
                } catch {
                    onEvent(.runtimeError("Failed to set multimeter beeper: \(error.localizedDescription)"))
                }

                while !Task.isCancelled {
                    if let rawMeasurement = try await driver.readMeasurement(at: Date()) {
                        let measurement = MeasurementAlertEvaluator.enrichMultimeter(
                            measurement: rawMeasurement,
                            configuration: alertConfiguration
                        )

                        do {
                            try await handleMultimeterOutputs(
                                measurement,
                                configuration: configuration,
                                csvLogger: csvLogger,
                                obsWriter: obsWriter
                            )
                        } catch {
                            onEvent(.runtimeError("Multimeter output write failed: \(error.localizedDescription)"))
                        }

                        onEvent(.multimeterMeasurement(measurement))
                    }

                    await sleep(seconds: sampleIntervalSeconds)
                }
            } catch {
                onEvent(.multimeterStatus(.error, "Multimeter error: \(error.localizedDescription)"))
            }

            await driver.disconnect()

            if Task.isCancelled || !reconnectEnabled {
                break
            }

            reconnectAttempt += 1
            let delay = reconnectDelay(forAttempt: reconnectAttempt)
            onEvent(.multimeterStatus(.connecting, "Retrying multimeter in \(String(format: "%.1f", delay))s"))
            await sleep(seconds: delay)
        }

        onEvent(.multimeterStatus(.disconnected, nil))
    }

    private static func runUsbCLoop(
        configuration: AppConfiguration,
        onEvent: @escaping @Sendable (RuntimeEvent) -> Void
    ) async {
        let reconnectEnabled = configuration.usbcAutoReconnect

        let csvLogger = CsvLogger()
        let obsWriter = ObsOutputWriter()
        var reconnectAttempt = 0

        while !Task.isCancelled {
            onEvent(.usbcStatus(.connecting, nil))

            let transport: any DeviceTransport
            if configuration.useSimulator {
                transport = SimulatedStreamingTransport(sampleRateHz: configuration.sampleRateHz)
            } else {
                let lineIO = POSIXSerialPort(
                    configuration: SerialPortConfiguration(
                        path: configuration.usbcPort,
                        baudRate: 9_600,
                        readTimeoutSeconds: 0.5,
                        writeTimeoutSeconds: 0.5
                    )
                )
                transport = StreamingSerialTransport(lineIO: lineIO)
            }
            let driver = UsbCDeviceDriver(transport: transport)

            do {
                try await driver.connect()
                reconnectAttempt = 0
                let source = configuration.useSimulator ? "simulator" : configuration.usbcPort
                onEvent(.usbcStatus(.connected, "USB-C meter connected (\(source))"))

                while !Task.isCancelled {
                    if let measurement = try await driver.readMeasurement(at: Date()) {
                        do {
                            try await handleUsbCOutputs(
                                measurement,
                                configuration: configuration,
                                csvLogger: csvLogger,
                                obsWriter: obsWriter
                            )
                        } catch {
                            onEvent(.runtimeError("USB-C output write failed: \(error.localizedDescription)"))
                        }

                        onEvent(.usbcMeasurement(measurement))
                    }
                }
            } catch {
                onEvent(.usbcStatus(.error, "USB-C error: \(error.localizedDescription)"))
            }

            await driver.disconnect()

            if Task.isCancelled || !reconnectEnabled {
                break
            }

            reconnectAttempt += 1
            let delay = reconnectDelay(forAttempt: reconnectAttempt)
            onEvent(.usbcStatus(.connecting, "Retrying USB-C meter in \(String(format: "%.1f", delay))s"))
            await sleep(seconds: delay)
        }

        onEvent(.usbcStatus(.disconnected, nil))
    }

    private static func reconnectDelay(forAttempt attempt: Int) -> TimeInterval {
        let initial = 0.5
        let raw = initial * pow(2.0, Double(max(0, attempt - 1)))
        return min(5.0, raw)
    }

    private static func sleep(seconds: TimeInterval) async {
        let clamped = max(0, seconds)
        let nanos = UInt64(clamped * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }

    private static func handleMultimeterOutputs(
        _ measurement: DeviceMeasurement,
        configuration: AppConfiguration,
        csvLogger: CsvLogger,
        obsWriter: ObsOutputWriter
    ) async throws {
        let display = MeasurementDisplayFormatter.multimeterPrimary(measurement)

        if configuration.multimeterCsvLoggingEnabled {
            try await csvLogger.logMultimeter(
                to: configuration.multimeterCsvLogFilePath,
                measurement: measurement,
                formattedValue: display
            )
        }

        try await obsWriter.writeMultimeter(
            to: configuration.multimeterOutputFile,
            mode: configuration.multimeterObsOutputMode,
            displayText: display,
            displayUnit: measurement.primaryUnit,
            modeText: MeasurementDisplayFormatter.multimeterModeTitle(measurement),
            label: configuration.multimeterValueLabel,
            customTemplate: configuration.multimeterObsCustomTemplate
        )
    }

    private static func handleUsbCOutputs(
        _ measurement: DeviceMeasurement,
        configuration: AppConfiguration,
        csvLogger: CsvLogger,
        obsWriter: ObsOutputWriter
    ) async throws {
        if configuration.usbcCsvLoggingEnabled {
            try await csvLogger.logUsbC(
                to: configuration.usbcCsvLogFilePath,
                measurement: measurement
            )
        }

        guard
            let voltage = measurement.primaryValue,
            let current = measurement.secondaryValue,
            let power = measurement.powerWatts
        else {
            return
        }

        try await obsWriter.writeUsbC(
            to: configuration.usbcOutputFile,
            mode: configuration.usbcObsOutputMode,
            voltage: voltage,
            current: current,
            power: power,
            label: configuration.usbcValueLabel,
            customTemplate: configuration.usbcObsCustomTemplate
        )
    }
}
