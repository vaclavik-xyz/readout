import Foundation

public actor ConfigurationStore {
    public let configFileURL: URL

    public init(configFileURL: URL) {
        self.configFileURL = configFileURL
    }

    public func hasPersistedConfiguration() -> Bool {
        FileManager.default.fileExists(atPath: configFileURL.path)
    }

    public func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            return AppConfiguration()
        }

        let data = try Data(contentsOf: configFileURL)
        return try AppConfiguration.fromJSONData(data)
    }

    public func save(_ configuration: AppConfiguration) throws {
        let directory = configFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let json = try JSONSerialization.data(
            withJSONObject: configuration.toDictionary(),
            options: [.prettyPrinted, .sortedKeys]
        )
        try json.write(to: configFileURL, options: [.atomic])
    }
}
