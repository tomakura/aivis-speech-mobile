import Foundation

public struct EngineRuntimeStatus: Codable, Equatable, Sendable {
    public enum Availability: String, Codable, Sendable {
        case linked
        case unavailable
    }

    public var providerName: String
    public var availability: Availability
    public var preferredExecutionProvider: String
    public var linkedVersion: String?
    public var coreMLAvailable: Bool
    public var notes: [String]

    public init(
        providerName: String,
        availability: Availability,
        preferredExecutionProvider: String,
        linkedVersion: String? = nil,
        coreMLAvailable: Bool,
        notes: [String] = []
    ) {
        self.providerName = providerName
        self.availability = availability
        self.preferredExecutionProvider = preferredExecutionProvider
        self.linkedVersion = linkedVersion
        self.coreMLAvailable = coreMLAvailable
        self.notes = notes
    }
}

public struct SupportedDevices: Codable, Equatable, Sendable {
    public var cpu: Bool
    public var gpu: Bool
    public var neuralEnginePreferred: Bool
    public var coreML: Bool

    public init(
        cpu: Bool = true,
        gpu: Bool = false,
        neuralEnginePreferred: Bool = false,
        coreML: Bool = false
    ) {
        self.cpu = cpu
        self.gpu = gpu
        self.neuralEnginePreferred = neuralEnginePreferred
        self.coreML = coreML
    }
}

public struct ModelStyle: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { localID }
    public var localID: Int
    public var name: String

    public init(localID: Int, name: String) {
        self.localID = localID
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case localID = "localId"
        case name
    }
}

public struct ModelSpeaker: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { uuid }
    public var uuid: UUID
    public var name: String
    public var styles: [ModelStyle]

    public init(uuid: UUID, name: String, styles: [ModelStyle]) {
        self.uuid = uuid
        self.name = name
        self.styles = styles
    }
}

public struct ModelStyleRuntimeMetadata: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { localID }
    public var localID: Int
    public var name: String
    public var vectorDimension: Int?
    public var notes: [String]

    public init(
        localID: Int,
        name: String,
        vectorDimension: Int? = nil,
        notes: [String] = []
    ) {
        self.localID = localID
        self.name = name
        self.vectorDimension = vectorDimension
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case localID = "localId"
        case name
        case vectorDimension
        case notes
    }
}

public struct ModelVectorRuntimeMetadata: Codable, Equatable, Sendable, Identifiable {
    public var id: String { key }
    public var key: String
    public var dimension: Int
    public var associatedStyleIDs: [Int]
    public var notes: [String]

    public init(
        key: String,
        dimension: Int,
        associatedStyleIDs: [Int] = [],
        notes: [String] = []
    ) {
        self.key = key
        self.dimension = dimension
        self.associatedStyleIDs = associatedStyleIDs
        self.notes = notes
    }
}

public struct ModelHyperParameterMetadata: Codable, Equatable, Sendable {
    public var speedScale: Double?
    public var intonationScale: Double?
    public var tempoDynamicsScale: Double?
    public var pitchScale: Double?
    public var volumeScale: Double?
    public var pauseLengthScale: Double?
    public var prePhonemeLength: Double?
    public var postPhonemeLength: Double?
    public var outputSamplingRate: Int?
    public var outputStereo: Bool?

    public init(
        speedScale: Double? = nil,
        intonationScale: Double? = nil,
        tempoDynamicsScale: Double? = nil,
        pitchScale: Double? = nil,
        volumeScale: Double? = nil,
        pauseLengthScale: Double? = nil,
        prePhonemeLength: Double? = nil,
        postPhonemeLength: Double? = nil,
        outputSamplingRate: Int? = nil,
        outputStereo: Bool? = nil
    ) {
        self.speedScale = speedScale
        self.intonationScale = intonationScale
        self.tempoDynamicsScale = tempoDynamicsScale
        self.pitchScale = pitchScale
        self.volumeScale = volumeScale
        self.pauseLengthScale = pauseLengthScale
        self.prePhonemeLength = prePhonemeLength
        self.postPhonemeLength = postPhonemeLength
        self.outputSamplingRate = outputSamplingRate
        self.outputStereo = outputStereo
    }
}

public struct ModelRuntimeDescriptor: Codable, Equatable, Sendable {
    public var styleProfiles: [ModelStyleRuntimeMetadata]
    public var vectorProfiles: [ModelVectorRuntimeMetadata]
    public var hyperParameters: ModelHyperParameterMetadata
    public var notes: [String]

    public init(
        styleProfiles: [ModelStyleRuntimeMetadata] = [],
        vectorProfiles: [ModelVectorRuntimeMetadata] = [],
        hyperParameters: ModelHyperParameterMetadata = ModelHyperParameterMetadata(),
        notes: [String] = []
    ) {
        self.styleProfiles = styleProfiles
        self.vectorProfiles = vectorProfiles
        self.hyperParameters = hyperParameters
        self.notes = notes
    }

    public var availableStyleIDs: [Int] {
        styleProfiles.map(\.localID)
    }
}

public struct ModelManifest: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { uuid }
    public var uuid: UUID
    public var name: String
    public var version: String
    public var modelArchitecture: String
    public var modelFormat: String
    public var speakers: [ModelSpeaker]
    public var runtimeDescriptor: ModelRuntimeDescriptor?

    public init(
        uuid: UUID,
        name: String,
        version: String,
        modelArchitecture: String,
        modelFormat: String,
        speakers: [ModelSpeaker],
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

public struct InstalledModel: Codable, Equatable, Sendable, Identifiable {
    public enum LoadState: String, Codable, Sendable {
        case installed
        case loaded
        case active
    }

    public var id: UUID
    public var name: String
    public var version: String
    public var sourceURL: URL?
    public var loadState: LoadState
    public var localFileURL: URL?
    public var lastLoadedAt: Date?
    public var manifest: ModelManifest?

    public init(
        id: UUID,
        name: String,
        version: String,
        sourceURL: URL? = nil,
        loadState: LoadState = .installed,
        localFileURL: URL? = nil,
        lastLoadedAt: Date? = nil,
        manifest: ModelManifest? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.sourceURL = sourceURL
        self.loadState = loadState
        self.localFileURL = localFileURL
        self.lastLoadedAt = lastLoadedAt
        self.manifest = manifest
    }
}

public protocol SpeechEngine: Sendable {
    func supportedDevices() async throws -> SupportedDevices
    func makeAudioQuery(text: String, styleID: Int) async throws -> AudioQuery
    func synthesize(query: AudioQuery, styleID: Int) async throws -> Data
}

public protocol ModelRepository: Sendable {
    func installedModels() async throws -> [InstalledModel]
    @discardableResult
    func installModel(fromFile fileURL: URL) async throws -> InstalledModel
    @discardableResult
    func installModel(fromRemote remoteURL: URL) async throws -> InstalledModel
    @discardableResult
    func updateModel(id: UUID) async throws -> InstalledModel
    func loadModel(id: UUID) async throws
    func activateModel(id: UUID) async throws
    func unloadModel(id: UUID) async throws
    func removeModel(id: UUID) async throws
}

public struct ModelInspectionSummary: Codable, Equatable, Sendable {
    public var inputNames: [String]
    public var outputNames: [String]
    public var inspectedAt: Date
    public var executionProvider: String?

    public init(
        inputNames: [String],
        outputNames: [String],
        inspectedAt: Date = Date(),
        executionProvider: String? = nil
    ) {
        self.inputNames = inputNames
        self.outputNames = outputNames
        self.inspectedAt = inspectedAt
        self.executionProvider = executionProvider
    }
}

public protocol InspectableModelRepository: ModelRepository {
    func inspection(for id: UUID) async throws -> ModelInspectionSummary
}

public protocol ProjectStore: Sendable {
    func loadProject(from fileURL: URL) async throws -> AISPProjectDocument
    func saveProject(_ project: AISPProjectDocument, to fileURL: URL) async throws
}

public protocol DictionaryStore: Sendable {
    func loadDictionary() async throws -> UserDictionary
    func saveDictionary(_ dictionary: UserDictionary) async throws
}

public protocol PresetStore: Sendable {
    func loadPresetCatalog() async throws -> PresetCatalog
    func savePresetCatalog(_ catalog: PresetCatalog) async throws
    func loadDefaultStyles() async throws -> [DefaultStyleID]
    func saveDefaultStyles(_ styles: [DefaultStyleID]) async throws
}
