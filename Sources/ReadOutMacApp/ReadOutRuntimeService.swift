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
        let uiEventRateHz = max(1, min(configuration.sampleRateHz, 12))
        let uiEmitIntervalSeconds = 1.0 / Double(uiEventRateHz)
        let alertConfiguration = configuration.alertConfiguration

        let csvLogger = CsvLogger()
        let obsWriter = ObsOutputWriter()
        let csvQueue = OutputWriteQueue(
            name: "multimeter-csv",
            capacity: configuration.outputQueueCapacity,
            maxRetryAttempts: configuration.outputQueueMaxRetryAttempts
        ) { level, message in
            onEvent(.runtimeLog(level, message))
        }
        let obsQueue = OutputWriteQueue(
            name: "multimeter-obs",
            capacity: configuration.outputQueueCapacity,
            maxRetryAttempts: configuration.outputQueueMaxRetryAttempts
        ) { level, message in
            onEvent(.runtimeLog(level, message))
        }
        onEvent(.runtimeLog(
            .info,
            "Output queues ready for multimeter (capacity \(configuration.outputQueueCapacity), retries \(configuration.outputQueueMaxRetryAttempts))."
        ))
        var reconnectAttempt = 0
        var lastUIEmitAt = Date.distantPast

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

                        await enqueueMultimeterOutputs(
                            measurement,
                            configuration: configuration,
                            csvLogger: csvLogger,
                            obsWriter: obsWriter,
                            csvQueue: csvQueue,
                            obsQueue: obsQueue
                        )

                        let now = Date()
                        if now.timeIntervalSince(lastUIEmitAt) >= uiEmitIntervalSeconds {
                            lastUIEmitAt = now
                            onEvent(.multimeterMeasurement(measurement))
                        }
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

        await csvQueue.shutdown(flush: true)
        await obsQueue.shutdown(flush: true)
        try? await csvLogger.flush()
        await csvLogger.close()
        try? await obsWriter.flush()
        onEvent(.multimeterStatus(.disconnected, nil))
    }

    private static func runUsbCLoop(
        configuration: AppConfiguration,
        onEvent: @escaping @Sendable (RuntimeEvent) -> Void
    ) async {
        let reconnectEnabled = configuration.usbcAutoReconnect
        let uiEventRateHz = max(1, min(configuration.sampleRateHz, 12))
        let uiEmitIntervalSeconds = 1.0 / Double(uiEventRateHz)

        let csvLogger = CsvLogger()
        let obsWriter = ObsOutputWriter()
        let csvQueue = OutputWriteQueue(
            name: "usbc-csv",
            capacity: configuration.outputQueueCapacity,
            maxRetryAttempts: configuration.outputQueueMaxRetryAttempts
        ) { level, message in
            onEvent(.runtimeLog(level, message))
        }
        let obsQueue = OutputWriteQueue(
            name: "usbc-obs",
            capacity: configuration.outputQueueCapacity,
            maxRetryAttempts: configuration.outputQueueMaxRetryAttempts
        ) { level, message in
            onEvent(.runtimeLog(level, message))
        }
        onEvent(.runtimeLog(
            .info,
            "Output queues ready for USB-C meter (capacity \(configuration.outputQueueCapacity), retries \(configuration.outputQueueMaxRetryAttempts))."
        ))
        var reconnectAttempt = 0
        var lastUIEmitAt = Date.distantPast

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
                        await enqueueUsbCOutputs(
                            measurement,
                            configuration: configuration,
                            csvLogger: csvLogger,
                            obsWriter: obsWriter,
                            csvQueue: csvQueue,
                            obsQueue: obsQueue
                        )

                        let now = Date()
                        if now.timeIntervalSince(lastUIEmitAt) >= uiEmitIntervalSeconds {
                            lastUIEmitAt = now
                            onEvent(.usbcMeasurement(measurement))
                        }
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

        await csvQueue.shutdown(flush: true)
        await obsQueue.shutdown(flush: true)
        try? await csvLogger.flush()
        await csvLogger.close()
        try? await obsWriter.flush()
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

    private static func enqueueMultimeterOutputs(
        _ measurement: DeviceMeasurement,
        configuration: AppConfiguration,
        csvLogger: CsvLogger,
        obsWriter: ObsOutputWriter,
        csvQueue: OutputWriteQueue,
        obsQueue: OutputWriteQueue
    ) async {
        let display = MeasurementDisplayFormatter.multimeterPrimary(measurement)
        let mode = MeasurementDisplayFormatter.multimeterModeTitle(measurement)

        if configuration.multimeterCsvLoggingEnabled {
            let csvPath = configuration.multimeterCsvLogFilePath
            let measurementSnapshot = measurement
            let displaySnapshot = display
            await csvQueue.enqueue {
                try await csvLogger.logMultimeter(
                    to: csvPath,
                    measurement: measurementSnapshot,
                    formattedValue: displaySnapshot
                )
            }
        }

        let outputPath = configuration.multimeterOutputFile
        if !outputPath.isEmpty {
            let outputMode = configuration.multimeterObsOutputMode
            let displayUnit = measurement.primaryUnit
            let label = configuration.multimeterValueLabel
            let template = configuration.multimeterObsCustomTemplate

            await obsQueue.enqueue {
                try await obsWriter.writeMultimeter(
                    to: outputPath,
                    mode: outputMode,
                    displayText: display,
                    displayUnit: displayUnit,
                    modeText: mode,
                    label: label,
                    customTemplate: template
                )
            }
        }
    }

    private static func enqueueUsbCOutputs(
        _ measurement: DeviceMeasurement,
        configuration: AppConfiguration,
        csvLogger: CsvLogger,
        obsWriter: ObsOutputWriter,
        csvQueue: OutputWriteQueue,
        obsQueue: OutputWriteQueue
    ) async {
        if configuration.usbcCsvLoggingEnabled {
            let csvPath = configuration.usbcCsvLogFilePath
            let measurementSnapshot = measurement
            await csvQueue.enqueue {
                try await csvLogger.logUsbC(
                    to: csvPath,
                    measurement: measurementSnapshot
                )
            }
        }

        guard
            let voltage = measurement.primaryValue,
            let current = measurement.secondaryValue,
            let power = measurement.powerWatts
        else {
            return
        }

        let outputPath = configuration.usbcOutputFile
        if !outputPath.isEmpty {
            let outputMode = configuration.usbcObsOutputMode
            let label = configuration.usbcValueLabel
            let template = configuration.usbcObsCustomTemplate
            await obsQueue.enqueue {
                try await obsWriter.writeUsbC(
                    to: outputPath,
                    mode: outputMode,
                    voltage: voltage,
                    current: current,
                    power: power,
                    label: label,
                    customTemplate: template
                )
            }
        }
    }
}
