import Foundation

/// Where the app keeps its few settings between launches: the library's filters and sort. Not records: the server
/// stays the only copy of anything in Enchiridion. Tests and previews keep nothing (`.none`) or keep it in memory.
public struct Preferences: Sendable {
    public var load: @Sendable (String) -> Data?
    public var save: @Sendable (String, Data) -> Void

    public init(load: @escaping @Sendable (String) -> Data?, save: @escaping @Sendable (String, Data) -> Void) {
        self.load = load
        self.save = save
    }

    /// Nothing remembered.
    public static let none = Preferences(load: { _ in nil }, save: { _, _ in })

    /// The app's own `UserDefaults`.
    public static let userDefaults = Preferences(
        load: { UserDefaults.standard.data(forKey: $0) },
        save: { UserDefaults.standard.set($1, forKey: $0) }
    )

    /// A value under `key`, nil when there is none or it no longer decodes (a field renamed since): defaults then.
    func value<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        load(key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func set(_ value: some Encodable, for key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        save(key, data)
    }
}
