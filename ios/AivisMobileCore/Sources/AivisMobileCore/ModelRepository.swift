import Foundation

public enum AIVMXModelArchitecture: String, Codable, Sendable {
    case styleBertVITS2 = "Style-Bert-VITS2"
    case styleBertVITS2JPExtra = "Style-Bert-VITS2 (JP-Extra)"
}

public enum AIVMXModelFormat: String, Codable, Sendable {
    case aivmx = "AIVMX"
    case onnx = "ONNX"
}

public struct AIVMXStyleManifest: Codable, Equatable, Sendable {
    public var localId: Int
    public var name: String

    public init(localId: Int, name: String) {
        self.localId = localId
        self.name = name
    }
}

public struct AIVMXSpeakerManifest: Codable, Equatable, Sendable {
    public var uuid: UUID
    public var name: String
    public var styles: [AIVMXStyleManifest]

    public init(uuid: UUID, name: String, styles: [AIVMXStyleManifest]) {
        self.uuid = uuid
        self.name = name
        self.styles = styles
    }
}

public struct AIVMXManifest: Codable, Equatable, Sendable {
    public var uuid: UUID
    public var name: String
    public var version: String
    public var modelArchitecture: AIVMXModelArchitecture
    public var modelFormat: AIVMXModelFormat
    public var speakers: [AIVMXSpeakerManifest]
    public var runtimeDescriptor: ModelRuntimeDescriptor?

    public init(
        uuid: UUID,
        name: String,
        version: String,
        modelArchitecture: AIVMXModelArchitecture,
        modelFormat: AIVMXModelFormat,
        speakers: [AIVMXSpeakerManifest],
        runtimeDescriptor: ModelRuntimeDescriptor? = nil
    ) {
        self.uuid = uuid
        self.name = name
        self.version = version
        self.modelArchitecture = modelArchitecture
        self.modelFormat = modelFormat
        self.speakers = speakers
        self.runtimeDescriptor = runtimeDescriptor
    }
}

public struct AIVMXLoadState: Codable, Equatable, Sendable {
    public var installed: Bool
    public var loaded: Bool
    public var active: Bool

    public init(installed: Bool, loaded: Bool, active: Bool = false) {
        self.installed = installed
        self.loaded = loaded
        self.active = active
    }

    enum CodingKeys: String, CodingKey {
        case installed
        case loaded
        case active
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        installed = try container.decode(Bool.self, forKey: .installed)
        loaded = try container.decode(Bool.self, forKey: .loaded)
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(installed, forKey: .installed)
        try container.encode(loaded, forKey: .loaded)
        try container.encode(active, forKey: .active)
    }
}

public struct AIVMXMetadataEnvelope: Codable, Equatable, Sendable {
    public var manifest: AIVMXManifest
    public var loadState: AIVMXLoadState

    public init(manifest: AIVMXManifest, loadState: AIVMXLoadState) {
        self.manifest = manifest
        self.loadState = loadState
    }
}

public struct ModelPackageRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var manifest: AIVMXManifest
    public var loadState: AIVMXLoadState
    public var sourceURL: URL?
    public var packageRelativePath: String
    public var metadataRelativePath: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastLoadedAt: Date?

    public init(
        id: UUID,
        manifest: AIVMXManifest,
        loadState: AIVMXLoadState,
        sourceURL: URL? = nil,
        packageRelativePath: String,
        metadataRelativePath: String,
        createdAt: Date,
        updatedAt: Date,
        lastLoadedAt: Date? = nil
    ) {
        self.id = id
        self.manifest = manifest
        self.loadState = loadState
        self.sourceURL = sourceURL
        self.packageRelativePath = packageRelativePath
        self.metadataRelativePath = metadataRelativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastLoadedAt = lastLoadedAt
    }
}

public struct ModelRepositorySnapshot: Codable, Equatable, Sendable {
    public var records: [ModelPackageRecord]

    public init(records: [ModelPackageRecord]) {
        self.records = records
    }
}

public enum ModelRepositoryError: LocalizedError, Equatable {
    case repositoryCorrupted
    case modelNotFound(UUID)
    case invalidSource(URL)
    case installFailed(URL)
    case updateUnavailable(UUID)

    public var errorDescription: String? {
        switch self {
        case .repositoryCorrupted:
            return "The model repository index could not be decoded."
        case let .modelNotFound(id):
            return "No model record exists for \(id.uuidString)."
        case let .invalidSource(url):
            return "The model source at \(url.absoluteString) is not readable."
        case let .installFailed(url):
            return "Failed to install the model from \(url.absoluteString)."
        case let .updateUnavailable(id):
            return "Model \(id.uuidString) cannot be updated because its source URL is unknown."
        }
    }
}

private struct RepositoryIndex: Codable, Equatable {
    var records: [ModelPackageRecord]
}

public actor FileModelRepository: ModelRepository {
    private let rootDirectory: URL
    private let modelsDirectory: URL
    private let indexURL: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var records: [UUID: ModelPackageRecord]

    public init(
        rootDirectory: URL,
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.rootDirectory = rootDirectory
        self.modelsDirectory = rootDirectory.appendingPathComponent("models", isDirectory: true)
        self.indexURL = rootDirectory.appendingPathComponent("model-index.json")
        self.fileManager = fileManager
        self.decoder = decoder
        self.encoder = encoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder.dateEncodingStrategy = .iso8601
        self.records = [:]

        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        if let loadedRecords = try? Self.loadIndex(
            from: indexURL,
            decoder: self.decoder
        ) {
            self.records = Dictionary(
                uniqueKeysWithValues: loadedRecords.records.map { record in
                    (record.id, record)
                }
            )
        }
    }

    public func snapshot() async throws -> ModelRepositorySnapshot {
        ModelRepositorySnapshot(records: sortedRecords())
    }

    public func record(id: UUID) async throws -> ModelPackageRecord {
        guard let record = records[id] else {
            throw ModelRepositoryError.modelNotFound(id)
        }
        return record
    }

    public func installedModels() async throws -> [InstalledModel] {
        sortedRecords().map { $0.installedModel(rootDirectory: rootDirectory) }
    }

    @discardableResult
    public func installModel(fromFile fileURL: URL) async throws -> InstalledModel {
        try await installModel(fromFile: fileURL, sourceURL: fileURL)
    }

    @discardableResult
    public func installModel(fromRemote remoteURL: URL) async throws -> InstalledModel {
        if remoteURL.isFileURL {
            return try await installModel(fromFile: remoteURL, sourceURL: remoteURL)
        }

        do {
            let (downloadedURL, _) = try await URLSession.shared.download(from: remoteURL)
            defer { try? fileManager.removeItem(at: downloadedURL) }
            return try await installModel(fromFile: downloadedURL, sourceURL: remoteURL)
        } catch {
            throw ModelRepositoryError.installFailed(remoteURL)
        }
    }

    @discardableResult
    public func updateModel(id: UUID) async throws -> InstalledModel {
        guard let record = records[id] else {
            throw ModelRepositoryError.modelNotFound(id)
        }

        guard let sourceURL = record.sourceURL else {
            throw ModelRepositoryError.updateUnavailable(id)
        }

        if sourceURL.isFileURL, fileManager.fileExists(atPath: sourceURL.path) {
            return try await installModel(
                fromFile: sourceURL,
                sourceURL: sourceURL,
                forcedIdentifier: id,
                preservingCreatedAt: record.createdAt,
                storageFilename: sourceURL.lastPathComponent
            )
        }

        do {
            let (downloadedURL, _) = try await URLSession.shared.download(from: sourceURL)
            defer { try? fileManager.removeItem(at: downloadedURL) }
            return try await installModel(
                fromFile: downloadedURL,
                sourceURL: sourceURL,
                forcedIdentifier: id,
                preservingCreatedAt: record.createdAt,
                storageFilename: sourceURL.lastPathComponent
            )
        } catch {
            throw ModelRepositoryError.installFailed(sourceURL)
        }
    }

    public func loadModel(id: UUID) async throws {
        try await mutateRecord(id: id) { record, now in
            record.loadState.installed = true
            record.loadState.loaded = true
            record.loadState.active = false
            record.lastLoadedAt = now
            record.updatedAt = now
        }
    }

    public func activateModel(id: UUID) async throws {
        for activeRecord in records.values where activeRecord.loadState.active && activeRecord.id != id {
            try await mutateRecord(id: activeRecord.id) { record, now in
                record.loadState.active = false
                record.loadState.loaded = true
                record.updatedAt = now
            }
        }

        try await mutateRecord(id: id) { record, now in
            record.loadState.installed = true
            record.loadState.loaded = true
            record.loadState.active = true
            record.lastLoadedAt = now
            record.updatedAt = now
        }
    }

    public func unloadModel(id: UUID) async throws {
        try await mutateRecord(id: id) { record, now in
            record.loadState.loaded = false
            record.loadState.active = false
            record.updatedAt = now
        }
    }

    public func removeModel(id: UUID) async throws {
        guard let record = records[id] else {
            throw ModelRepositoryError.modelNotFound(id)
        }

        let packageURL = rootDirectory.appendingPathComponent(record.packageRelativePath)
        let metadataURL = rootDirectory.appendingPathComponent(record.metadataRelativePath)
        let modelDirectory = packageURL.deletingLastPathComponent()

        records.removeValue(forKey: id)
        try? fileManager.removeItem(at: metadataURL)
        try? fileManager.removeItem(at: modelDirectory)
        try persistIndex()
    }

    private func installModel(
        fromFile fileURL: URL,
        sourceURL: URL,
        forcedIdentifier: UUID? = nil,
        preservingCreatedAt: Date? = nil,
        storageFilename: String? = nil
    ) async throws -> InstalledModel {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ModelRepositoryError.invalidSource(fileURL)
        }

        let envelope = try loadEnvelope(for: fileURL)
        let normalizedManifest = normalizeManifest(envelope.manifest, sourceFileURL: fileURL)

        let identifier = forcedIdentifier ?? normalizedManifest.uuid
        let now = Date()
        let packageFilename = storageFilename ?? fileURL.lastPathComponent
        let packageRelativePath = "models/\(identifier.uuidString)/\(packageFilename)"
        let metadataRelativePath = "models/\(identifier.uuidString)/metadata.json"
        let packageURL = rootDirectory.appendingPathComponent(packageRelativePath)
        let metadataURL = rootDirectory.appendingPathComponent(metadataRelativePath)

        try fileManager.createDirectory(
            at: packageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }

        try fileManager.copyItem(at: fileURL, to: packageURL)

        let record = ModelPackageRecord(
            id: identifier,
            manifest: AIVMXManifest(
                uuid: identifier,
                name: normalizedManifest.name,
                version: normalizedManifest.version,
                modelArchitecture: normalizedManifest.modelArchitecture,
                modelFormat: normalizedManifest.modelFormat,
                speakers: normalizedManifest.speakers,
                runtimeDescriptor: normalizedManifest.runtimeDescriptor
            ),
            loadState: normalizedLoadState(envelope.loadState),
            sourceURL: sourceURL,
            packageRelativePath: packageRelativePath,
            metadataRelativePath: metadataRelativePath,
            createdAt: preservingCreatedAt ?? now,
            updatedAt: now,
            lastLoadedAt: envelope.loadState.loaded ? now : nil
        )

        try persist(record: record, metadataURL: metadataURL)
        records[identifier] = record
        try persistIndex()

        return record.installedModel(rootDirectory: rootDirectory)
    }

    private func mutateRecord(
        id: UUID,
        mutation: (inout ModelPackageRecord, Date) -> Void
    ) async throws {
        guard var record = records[id] else {
            throw ModelRepositoryError.modelNotFound(id)
        }

        let now = Date()
        mutation(&record, now)
        records[id] = record
        let metadataURL = rootDirectory.appendingPathComponent(record.metadataRelativePath)
        try persist(record: record, metadataURL: metadataURL)
        try persistIndex()
    }

    private func persist(record: ModelPackageRecord, metadataURL: URL) throws {
        let envelope = AIVMXMetadataEnvelope(
            manifest: record.manifest,
            loadState: record.loadState
        )
        let data = try encoder.encode(envelope)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func persistIndex() throws {
        let index = RepositoryIndex(records: sortedRecords())
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    private func sortedRecords() -> [ModelPackageRecord] {
        records.values.sorted { lhs, rhs in
            lhs.manifest.name.localizedCaseInsensitiveCompare(rhs.manifest.name) == .orderedAscending
        }
    }

    private static func loadIndex(from url: URL, decoder: JSONDecoder) throws -> RepositoryIndex {
        let data = try Data(contentsOf: url)
        return try decoder.decode(RepositoryIndex.self, from: data)
    }

    private static func makeFallbackEnvelope(for fileURL: URL) -> AIVMXMetadataEnvelope {
        let identifier = UUID()
        let speakerID = UUID()
        return AIVMXMetadataEnvelope(
            manifest: AIVMXManifest(
                uuid: identifier,
                name: fileURL.deletingPathExtension().lastPathComponent,
                version: "imported",
                modelArchitecture: .styleBertVITS2,
                modelFormat: .aivmx,
                speakers: [
                    AIVMXSpeakerManifest(
                        uuid: speakerID,
                        name: "Imported Speaker",
                        styles: [AIVMXStyleManifest(localId: 0, name: "Normal")]
                    )
                ],
                runtimeDescriptor: defaultRuntimeDescriptor(
                    styleIDs: [0],
                    speakerName: "Imported Speaker",
                    modelName: fileURL.deletingPathExtension().lastPathComponent
                )
            ),
            loadState: AIVMXLoadState(installed: true, loaded: false, active: false)
        )
    }

    private func normalizeManifest(
        _ manifest: AIVMXManifest,
        sourceFileURL: URL
    ) -> AIVMXManifest {
        let derivedStyleIDs = manifest.speakers.flatMap(\.styles).map(\.localId)
        let runtimeDescriptor = manifest.runtimeDescriptor ?? Self.defaultRuntimeDescriptor(
            styleIDs: derivedStyleIDs.isEmpty ? [0] : derivedStyleIDs,
            speakerName: manifest.speakers.first?.name ?? sourceFileURL.deletingPathExtension().lastPathComponent,
            modelName: manifest.name
        )

        let speakers = manifest.speakers.isEmpty
            ? Self.fallbackSpeakers(
                modelName: manifest.name,
                sourceFileURL: sourceFileURL,
                styleIDs: runtimeDescriptor.availableStyleIDs
            )
            : manifest.speakers

        return AIVMXManifest(
            uuid: manifest.uuid,
            name: manifest.name,
            version: manifest.version,
            modelArchitecture: manifest.modelArchitecture,
            modelFormat: manifest.modelFormat,
            speakers: speakers,
            runtimeDescriptor: runtimeDescriptor
        )
    }

    private static func fallbackSpeakers(
        modelName: String,
        sourceFileURL: URL,
        styleIDs: [Int]
    ) -> [AIVMXSpeakerManifest] {
        [
            AIVMXSpeakerManifest(
                uuid: UUID(),
                name: modelName.isEmpty ? sourceFileURL.deletingPathExtension().lastPathComponent : modelName,
                styles: styleIDs.isEmpty
                    ? [AIVMXStyleManifest(localId: 0, name: "Normal")]
                    : styleIDs.map { styleID in
                        AIVMXStyleManifest(localId: styleID, name: styleID == 0 ? "Normal" : "Style \(styleID)")
                    }
            )
        ]
    }

    private static func defaultRuntimeDescriptor(
        styleIDs: [Int],
        speakerName: String,
        modelName: String
    ) -> ModelRuntimeDescriptor {
        let normalizedStyleIDs = Array(Set(styleIDs)).sorted()
        let styleProfiles = normalizedStyleIDs.map { styleID in
            ModelStyleRuntimeMetadata(
                localID: styleID,
                name: styleID == 0 ? "Normal" : "Style \(styleID)",
                vectorDimension: 256,
                notes: [
                    "Synthesized from imported \(modelName) metadata",
                    "Speaker: \(speakerName)"
                ]
            )
        }

        let vectorProfiles = [
            ModelVectorRuntimeMetadata(
                key: "speaker_embedding",
                dimension: max(128, normalizedStyleIDs.count * 64),
                associatedStyleIDs: normalizedStyleIDs,
                notes: [
                    "Fallback vector metadata synthesized during import",
                    "Used to preserve runtime contract shape"
                ]
            )
        ]

        let hyperParameters = ModelHyperParameterMetadata(
            speedScale: 1.0,
            intonationScale: 1.0,
            tempoDynamicsScale: 1.0,
            pitchScale: 0.0,
            volumeScale: 1.0,
            pauseLengthScale: 1.0,
            prePhonemeLength: 0.1,
            postPhonemeLength: 0.1,
            outputSamplingRate: 44_100,
            outputStereo: false
        )

        return ModelRuntimeDescriptor(
            styleProfiles: styleProfiles.isEmpty
                ? [ModelStyleRuntimeMetadata(localID: 0, name: "Normal", vectorDimension: 256, notes: ["Synthesized fallback style"])]
                : styleProfiles,
            vectorProfiles: vectorProfiles,
            hyperParameters: hyperParameters,
            notes: [
                "Runtime descriptor synthesized because the imported package omitted one.",
                "Contract preserved for active-model-aware preview synthesis."
            ]
        )
    }

    private func normalizedLoadState(_ loadState: AIVMXLoadState) -> AIVMXLoadState {
        AIVMXLoadState(
            installed: loadState.installed || loadState.loaded || loadState.active,
            loaded: loadState.loaded || loadState.active,
            active: loadState.active
        )
    }

    private func loadEnvelope(for fileURL: URL) throws -> AIVMXMetadataEnvelope {
        let data = try Data(contentsOf: fileURL)
        if let envelope = try? decoder.decode(AIVMXMetadataEnvelope.self, from: data) {
            return envelope
        }

        if let sidecarURL = metadataSidecarURL(for: fileURL) {
            let sidecarData = try Data(contentsOf: sidecarURL)
            if let envelope = try? decoder.decode(AIVMXMetadataEnvelope.self, from: sidecarData) {
                return envelope
            }
        }

        if let envelope = try? AIVMXEmbeddedMetadataParser.envelope(from: data) {
            return envelope
        }

        return Self.makeFallbackEnvelope(for: fileURL)
    }

    private func metadataSidecarURL(for fileURL: URL) -> URL? {
        let baseURL = fileURL.deletingPathExtension()
        let candidates = [
            baseURL.appendingPathExtension("json"),
            fileURL.appendingPathExtension("json"),
            baseURL.appendingPathExtension("metadata.json"),
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }
}

private extension ModelPackageRecord {
    func installedModel(rootDirectory: URL) -> InstalledModel {
        InstalledModel(
            id: id,
            name: manifest.name,
            version: manifest.version,
            sourceURL: sourceURL,
            loadState: installedModelLoadState,
            localFileURL: rootDirectory.appendingPathComponent(packageRelativePath),
            lastLoadedAt: lastLoadedAt,
            manifest: ModelManifest(
                uuid: manifest.uuid,
                name: manifest.name,
                version: manifest.version,
                modelArchitecture: manifest.modelArchitecture.rawValue,
                modelFormat: manifest.modelFormat.rawValue,
                speakers: manifest.speakers.map { speaker in
                    ModelSpeaker(
                        uuid: speaker.uuid,
                        name: speaker.name,
                        styles: speaker.styles.map { style in
                            ModelStyle(localID: style.localId, name: style.name)
                        }
                    )
                },
                runtimeDescriptor: manifest.runtimeDescriptor
            )
        )
    }

    var installedModelLoadState: InstalledModel.LoadState {
        if loadState.active {
            return .active
        }
        if loadState.loaded {
            return .loaded
        }
        return .installed
    }
}
