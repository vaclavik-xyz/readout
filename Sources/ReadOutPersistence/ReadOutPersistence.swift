import Foundation
import ReadOutCore

public struct PersistencePaths: Sendable, Equatable {
    public var configFile: URL
    public var logsDirectory: URL
    public var outputDirectory: URL

    public init(configFile: URL, logsDirectory: URL, outputDirectory: URL) {
        self.configFile = configFile
        self.logsDirectory = logsDirectory
        self.outputDirectory = outputDirectory
    }
}

public enum ReadOutPersistenceBootstrap {
    public static let note = "Config, CSV logging, and OBS-compatible text output will be implemented in the next milestone."
}
