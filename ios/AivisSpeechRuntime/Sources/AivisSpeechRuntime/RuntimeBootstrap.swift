import Foundation
import AivisMobileCore

public struct RuntimeLaunchSnapshot: Sendable, Equatable {
    public var runtimeStatus: EngineRuntimeStatus
    public var supportedDevices: SupportedDevices
    public var installedModels: [InstalledModel]

    public init(
        runtimeStatus: EngineRuntimeStatus,
        supportedDevices: SupportedDevices,
        installedModels: [InstalledModel]
    ) {
        self.runtimeStatus = runtimeStatus
        self.supportedDevices = supportedDevices
        self.installedModels = installedModels
    }
}

public struct ModelRuntimePreparation: Sendable, Equatable {
    public var model: InstalledModel
    public var session: ONNXSessionBootstrap
    public var inspection: ONNXModelInspection

    public init(
        model: InstalledModel,
        session: ONNXSessionBootstrap,
        inspection: ONNXModelInspection
    ) {
        self.model = model
        self.session = session
        self.inspection = inspection
    }

    public var displayTitle: String {
        model.name
    }

    public var displaySubtitle: String {
        "\(session.modeLabel.capitalized) session · \(session.preferredExecutionProvider)"
    }

    public var badges: [String] {
        [
            model.loadState.rawValue,
            "\(inspection.inputNames.count) inputs",
            "\(inspection.outputNames.count) outputs",
        ]
    }
}

public enum RuntimeBootstrapError: LocalizedError {
    case applicationSupportDirectoryUnavailable
    case missingSeedModelResource
    case missingSeedMetadataResource

    public var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return "Application Support directory is unavailable."
        case .missingSeedModelResource:
            return "Bundled sample ONNX resource is missing."
        case .missingSeedMetadataResource:
            return "Bundled sample model metadata resource is missing."
        }
    }
}

public actor ORTModelRepository: InspectableModelRepository {
    private let baseRepository: FileModelRepository
    private let sessionCache: ONNXSessionCache

    public init(
        baseRepository: FileModelRepository,
        sessionCache: ONNXSessionCache = ONNXRuntimeSupport.sharedSessionCache
    ) {
        self.baseRepository = baseRepository
        self.sessionCache = sessionCache
    }

    public func installedModels() async throws -> [InstalledModel] {
        try await baseRepository.installedModels()
    }

    @discardableResult
    public func installModel(fromFile fileURL: URL) async throws -> InstalledModel {
        try await baseRepository.installModel(fromFile: fileURL)
    }

    @discardableResult
    public func installModel(fromRemote remoteURL: URL) async throws -> InstalledModel {
        try await baseRepository.installModel(fromRemote: remoteURL)
    }

    @discardableResult
    public func updateModel(id: UUID) async throws -> InstalledModel {
        let updated = try await baseRepository.updateModel(id: id)
        if let localFileURL = updated.localFileURL {
            sessionCache.invalidateSessions(for: localFileURL)
        }
        return updated
    }

    public func loadModel(id: UUID) async throws {
        let model = try await installedModel(id: id)
        try createSessionIfPossible(for: model)
        try await baseRepository.loadModel(id: id)
    }

    public func activateModel(id: UUID) async throws {
        let model = try await installedModel(id: id)
        try createSessionIfPossible(for: model)
        try await baseRepository.activateModel(id: id)
    }

    public func unloadModel(id: UUID) async throws {
        let model = try await installedModel(id: id)
        if let localFileURL = model.localFileURL {
            sessionCache.invalidateSessions(for: localFileURL)
        }
        try await baseRepository.unloadModel(id: id)
    }

    public func removeModel(id: UUID) async throws {
        let model = try await installedModel(id: id)
        if let localFileURL = model.localFileURL {
            sessionCache.invalidateSessions(for: localFileURL)
        }
        try await baseRepository.removeModel(id: id)
    }

    public func inspection(for id: UUID) async throws -> ModelInspectionSummary {
        let inspection = try await inspectModel(id: id)
        let bootstrap = try await bootstrapSession(for: id)
        return ModelInspectionSummary(
            inputNames: inspection.inputNames,
            outputNames: inspection.outputNames,
            executionProvider: bootstrap.preferredExecutionProvider
        )
    }

    public func inspectModel(id: UUID) async throws -> ONNXModelInspection {
        let model = try await installedModel(id: id)
        guard let localFileURL = model.localFileURL else {
            throw ModelRepositoryError.modelNotFound(id)
        }
        return try ONNXRuntimeSupport.inspectModel(at: localFileURL)
    }

    public func bootstrapSession(
        for id: UUID,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false
    ) async throws -> ONNXSessionBootstrap {
        let model = try await installedModel(id: id)
        return try bootstrapSession(
            for: model,
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly
        )
    }

    public func bootstrapSession(
        for model: InstalledModel,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false
    ) throws -> ONNXSessionBootstrap {
        guard let localFileURL = model.localFileURL else {
            throw ModelRepositoryError.modelNotFound(model.id)
        }

        let handle = try sessionCache.sessionHandle(
            for: localFileURL,
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly
        )
        return handle.bootstrapSummary
    }

    public func prepareModelRuntime(
        for id: UUID,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false
    ) async throws -> ModelRuntimePreparation {
        let model = try await installedModel(id: id)
        return try prepareModelRuntime(
            for: model,
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly
        )
    }

    public func prepareModelRuntime(
        for model: InstalledModel,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false
    ) throws -> ModelRuntimePreparation {
        let bootstrap = try bootstrapSession(
            for: model,
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly
        )
        let inspection = try ONNXRuntimeSupport.inspectModel(
            at: bootstrap.modelURL,
            preferCoreML: preferCoreML
        )
        return ModelRuntimePreparation(
            model: model,
            session: bootstrap,
            inspection: inspection
        )
    }

    private func installedModel(id: UUID) async throws -> InstalledModel {
        let models = try await baseRepository.installedModels()
        guard let model = models.first(where: { $0.id == id }) else {
            throw ModelRepositoryError.modelNotFound(id)
        }
        return model
    }

    private func createSessionIfPossible(for model: InstalledModel) throws {
        guard let localFileURL = model.localFileURL else {
            throw ModelRepositoryError.modelNotFound(model.id)
        }
        _ = try sessionCache.sessionHandle(for: localFileURL, preferCoreML: true, staticInputShapesOnly: false)
    }
}

public struct RuntimeBootstrapResult: Sendable {
    public var repository: ORTModelRepository
    public var snapshot: RuntimeLaunchSnapshot
    public var speechEngine: any SpeechEngine

    public init(
        repository: ORTModelRepository,
        snapshot: RuntimeLaunchSnapshot,
        speechEngine: any SpeechEngine
    ) {
        self.repository = repository
        self.snapshot = snapshot
        self.speechEngine = speechEngine
    }
}

public enum RuntimeBootstrap {
    public static func bootstrapDefault() async throws -> RuntimeBootstrapResult {
        let baseRepository = FileModelRepository(rootDirectory: try defaultRepositoryRoot())
        try await seedBundledModelIfNeeded(into: baseRepository)
        let wrappedRepository = ORTModelRepository(baseRepository: baseRepository)
        let installedModels = try await wrappedRepository.installedModels()
        if installedModels.contains(where: { $0.loadState == .active }) == false, let firstModel = installedModels.first {
            try await wrappedRepository.activateModel(id: firstModel.id)
        }
        var runtimeStatus = ONNXRuntimeSupport.statusSnapshot()
        runtimeStatus.notes.append("Speech generation uses the native Style-Bert-VITS2 path by default. Remote AivisSpeech Engine is an explicit development override only.")
        runtimeStatus.notes.append("Japanese text analysis uses the bundled on-device OpenJTalk frontend.")
        let snapshot = RuntimeLaunchSnapshot(
            runtimeStatus: runtimeStatus,
            supportedDevices: ONNXRuntimeSupport.supportedDevices(),
            installedModels: try await wrappedRepository.installedModels()
        )
        let nativeEngine = StyleBertVITS2SpeechEngine(modelRepository: wrappedRepository)
        return RuntimeBootstrapResult(
            repository: wrappedRepository,
            snapshot: snapshot,
            speechEngine: UserDefaultsConfiguredSpeechEngine(
                nativeEngine: nativeEngine,
                modelRepository: wrappedRepository
            )
        )
    }

    static func defaultRepositoryRoot() throws -> URL {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw RuntimeBootstrapError.applicationSupportDirectoryUnavailable
        }
        return appSupportURL
            .appendingPathComponent("AivisSpeechMobile", isDirectory: true)
            .appendingPathComponent("ModelRepository", isDirectory: true)
    }

    static func seedBundledModelIfNeeded(into repository: FileModelRepository) async throws {
        let snapshot = try await repository.snapshot()
        if !snapshot.records.isEmpty {
            return
        }

        guard let bundledModelURL = Bundle.module.url(forResource: "sample_runtime_seed", withExtension: "onnx") else {
            throw RuntimeBootstrapError.missingSeedModelResource
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let primaryManifest = try seedManifest()
        let secondaryManifest = AIVMXManifest(
            uuid: UUID(uuidString: "6ad4f1d8-024a-4dc7-b0d8-24bce9822489") ?? UUID(),
            name: "Misty Narrator",
            version: "0.9.2",
            modelArchitecture: primaryManifest.modelArchitecture,
            modelFormat: primaryManifest.modelFormat,
            speakers: primaryManifest.speakers
        )

        try await installSeedModel(
            manifest: primaryManifest,
            repository: repository,
            bundledModelURL: bundledModelURL,
            temporaryDirectory: temporaryDirectory
        )
        try await installSeedModel(
            manifest: secondaryManifest,
            repository: repository,
            bundledModelURL: bundledModelURL,
            temporaryDirectory: temporaryDirectory
        )
    }

    private static func seedManifest() throws -> AIVMXManifest {
        guard let metadataURL = Bundle.module.url(
            forResource: "aivmx-metadata.sample",
            withExtension: "json"
        ) else {
            throw RuntimeBootstrapError.missingSeedMetadataResource
        }

        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(AIVMXMetadataEnvelope.self, from: data).manifest
    }

    private static func installSeedModel(
        manifest: AIVMXManifest,
        repository: FileModelRepository,
        bundledModelURL: URL,
        temporaryDirectory: URL
    ) async throws {
        let modelURL = temporaryDirectory.appendingPathComponent("\(manifest.name.replacingOccurrences(of: " ", with: "-")).onnx")
        let sidecarURL = modelURL.deletingPathExtension().appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
        try FileManager.default.copyItem(at: bundledModelURL, to: modelURL)

        let envelope = AIVMXMetadataEnvelope(
            manifest: manifest,
            loadState: AIVMXLoadState(installed: true, loaded: false, active: false)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(envelope).write(to: sidecarURL, options: .atomic)

        _ = try await repository.installModel(fromFile: modelURL)
    }
}
