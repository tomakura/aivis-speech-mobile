import Foundation

public enum SharedUserDictionaryStorage {
    public static let userDefaultsKey = "AivisSharedUserDictionary"

    public static func load(from defaults: UserDefaults = .standard) -> UserDictionary? {
        guard let data = defaults.data(forKey: userDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(UserDictionary.self, from: data)
    }

    public static func save(_ dictionary: UserDictionary, to defaults: UserDefaults = .standard) throws {
        let data = try JSONEncoder().encode(dictionary)
        defaults.set(data, forKey: userDefaultsKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}
