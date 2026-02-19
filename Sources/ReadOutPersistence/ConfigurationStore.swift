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
        let migrated = try LegacyConfigMigrator.migrateKeys(in: data)
        return try JSONDecoder().decode(AppConfiguration.self, from: migrated)
    }

    public func save(_ configuration: AppConfiguration) throws {
        let directory = configFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: configFileURL, options: [.atomic])
    }
}
