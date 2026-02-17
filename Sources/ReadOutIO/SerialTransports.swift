import Foundation

public actor StreamingSerialTransport: DeviceTransport {
    private let lineIO: any SerialLineIO

    public init(lineIO: any SerialLineIO) {
        self.lineIO = lineIO
    }

    public func open() async throws {
        try await lineIO.open()
    }

    public func close() async {
        await lineIO.close()
    }

    public func readFrame() async throws -> String? {
        try await lineIO.readLine()
    }
}

public actor SCPIPollingTransport: DeviceTransport {
    private let lineIO: any SerialLineIO
    private let primaryCommand: String
    private let fallbackCommands: [String]

    public init(
        lineIO: any SerialLineIO,
        primaryCommand: String = "MEAS?",
        fallbackCommands: [String] = ["MEAS1:SHOW?"]
    ) {
        self.lineIO = lineIO
        self.primaryCommand = primaryCommand
        self.fallbackCommands = fallbackCommands
    }

    public func open() async throws {
        try await lineIO.open()
    }

    public func close() async {
        await lineIO.close()
    }

    public func readFrame() async throws -> String? {
        for command in [primaryCommand] + fallbackCommands {
            let response = try await query(command)
            if let response, !response.isEmpty {
                return response
            }
        }
        return nil
    }

    public func query(_ command: String) async throws -> String? {
        try await lineIO.writeLine(command)
        return try await lineIO.readLine()
    }
}
