import Foundation

/// Preprocesses raw JSON data to rename legacy Python-era keys before Codable decoding.
/// Each legacy key is only migrated when the corresponding current key is absent or has
/// its default value, preserving explicit overrides in user config files.
public enum LegacyConfigMigrator {
    private struct Migration: Sendable {
        let legacy: String
        let current: String
        let shouldApply: @Sendable (Any) -> Bool
    }

    private static func isEmptyOrAbsent(_ existing: Any) -> Bool {
        (existing as? String ?? "").isEmpty
    }

    private static func isDefaultObsTemplate(_ existing: Any) -> Bool {
        guard let s = existing as? String else { return true }
        return s.uppercased() == "{VALUE} {UNIT}" || s == "{value} {unit}"
    }

    private static func isDefaultObsMode(_ existing: Any) -> Bool {
        guard let s = existing as? String else { return true }
        return s.uppercased() == "VALUE_AND_UNIT"
    }

    private static func isFalse(_ existing: Any) -> Bool {
        (existing as? Bool) == false
    }

    private static let migrations: [Migration] = [
        Migration(legacy: "port", current: "multimeter_port", shouldApply: isEmptyOrAbsent),
        Migration(legacy: "output_file", current: "multimeter_output_file", shouldApply: isEmptyOrAbsent),
        Migration(legacy: "obs_custom_template", current: "multimeter_obs_custom_template", shouldApply: isDefaultObsTemplate),
        Migration(legacy: "obs_output_mode", current: "multimeter_obs_output_mode", shouldApply: isDefaultObsMode),
        Migration(legacy: "value_label", current: "multimeter_value_label", shouldApply: isEmptyOrAbsent),
        Migration(legacy: "csv_log_file_path", current: "multimeter_csv_log_file_path", shouldApply: isEmptyOrAbsent),
        Migration(legacy: "csv_logging_enabled", current: "multimeter_csv_logging_enabled", shouldApply: isFalse),
    ]

    public static func migrateKeys(in data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard var dictionary = object as? [String: Any] else {
            throw ConfigurationStoreError.invalidFormat
        }

        for migration in migrations {
            guard let legacyValue = dictionary[migration.legacy] else {
                continue
            }

            let shouldApply: Bool
            if let existing = dictionary[migration.current] {
                shouldApply = migration.shouldApply(existing)
            } else {
                shouldApply = true
            }

            if shouldApply {
                dictionary[migration.current] = legacyValue
            }
        }

        return try JSONSerialization.data(withJSONObject: dictionary, options: [])
    }
}
