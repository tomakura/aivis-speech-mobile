import Foundation

actor JSONFileStore<Value: Codable & Sendable> {
    private let fileURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        fileURL: URL,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.fileURL = fileURL
        self.decoder = decoder
        self.encoder = encoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() async throws -> Value {
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) async throws {
        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }
}

public actor FileProjectStore: ProjectStore {
    private let migrator: ProjectMigrator
    private let encoder: JSONEncoder

    public init(
        migrator: ProjectMigrator = ProjectMigrator(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.migrator = migrator
        self.encoder = encoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func loadProject(from fileURL: URL) async throws -> AISPProjectDocument {
        let data = try Data(contentsOf: fileURL)
        return try migrator.migrate(data: data)
    }

    public func saveProject(_ project: AISPProjectDocument, to fileURL: URL) async throws {
        let data = try encoder.encode(project)
        try data.write(to: fileURL, options: .atomic)
    }
}

public actor FilePresetStore: PresetStore {
    private let presetCatalogStore: JSONFileStore<PresetCatalog>
    private let defaultStylesStore: JSONFileStore<[DefaultStyleID]>

    public init(
        presetCatalogURL: URL,
        defaultStylesURL: URL,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.presetCatalogStore = JSONFileStore(
            fileURL: presetCatalogURL,
            decoder: decoder,
            encoder: encoder
        )
        self.defaultStylesStore = JSONFileStore(
            fileURL: defaultStylesURL,
            decoder: decoder,
            encoder: encoder
        )
    }

    public func loadPresetCatalog() async throws -> PresetCatalog {
        try await presetCatalogStore.load()
    }

    public func savePresetCatalog(_ catalog: PresetCatalog) async throws {
        try await presetCatalogStore.save(catalog)
    }

    public func loadDefaultStyles() async throws -> [DefaultStyleID] {
        try await defaultStylesStore.load()
    }

    public func saveDefaultStyles(_ styles: [DefaultStyleID]) async throws {
        try await defaultStylesStore.save(styles)
    }
}

public actor InMemoryDictionaryStore: DictionaryStore {
    private var dictionary: UserDictionary

    public init(dictionary: UserDictionary = UserDictionary(entries: [])) {
        self.dictionary = dictionary
    }

    public func loadDictionary() async throws -> UserDictionary {
        dictionary
    }

    public func saveDictionary(_ dictionary: UserDictionary) async throws {
        self.dictionary = dictionary
    }
}

public actor FileDictionaryStore: DictionaryStore {
    private let store: JSONFileStore<UserDictionary>

    public init(
        fileURL: URL,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.store = JSONFileStore(fileURL: fileURL, decoder: decoder, encoder: encoder)
    }

    public func loadDictionary() async throws -> UserDictionary {
        try await store.load()
    }

    public func saveDictionary(_ dictionary: UserDictionary) async throws {
        try await store.save(dictionary)
    }
}
