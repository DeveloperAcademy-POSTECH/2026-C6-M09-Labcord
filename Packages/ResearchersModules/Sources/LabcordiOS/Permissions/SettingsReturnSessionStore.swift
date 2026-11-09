import Foundation

@MainActor
public enum SettingsReturnSessionStore {
    private static let key = "settingsReturnExperimentID"

    public static var experimentID: UUID? {
        UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    public static func save(_ experimentID: UUID) {
        UserDefaults.standard.set(experimentID.uuidString, forKey: key)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
