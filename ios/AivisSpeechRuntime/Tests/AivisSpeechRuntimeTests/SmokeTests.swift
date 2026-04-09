import Foundation
import Testing
import AivisMobileCore
@testable import AivisSpeechRuntime

@Test
func runtimeStatusDefaultsToLinkedCoreML() {
    let snapshot = ONNXRuntimeSupport.statusSnapshot()
    #expect(snapshot.availability == .linked)
    #expect(snapshot.providerName == "ONNX Runtime Mobile")
    #expect(!snapshot.preferredExecutionProvider.isEmpty)
}

@Test
func canCreateEnvironmentAndSessionOptions() throws {
    let environment = try ONNXRuntimeSupport.makeEnvironment()
    let sessionOptions = try ONNXRuntimeSupport.makeSessionOptions()
    #expect(String(describing: environment).contains("ORTEnv"))
    #expect(String(describing: sessionOptions).contains("ORTSessionOptions"))
}

@Test
func runtimeRepositoryActivatesBundledSeedModel() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let bundledModelURL = try FixtureBootstrap.fixtureURL(
        "ios/AivisSpeechRuntime/Sources/AivisSpeechRuntime/Resources/sample_runtime_seed.onnx"
    )
    let importedModelURL = temporaryDirectory.appendingPathComponent("sample_runtime_seed.onnx")
    try FileManager.default.copyItem(at: bundledModelURL, to: importedModelURL)

    let sidecarURL = temporaryDirectory.appendingPathComponent("sample_runtime_seed.json")
    try FixtureBootstrap.loadFixtureData("shared/fixtures/models/aivmx-metadata.sample.json")
        .write(to: sidecarURL, options: .atomic)

    let baseRepository = FileModelRepository(rootDirectory: temporaryDirectory.appendingPathComponent("repository", isDirectory: true))
    _ = try await baseRepository.installModel(fromFile: importedModelURL)

    let cache = ONNXSessionCache { url, preferCoreML, staticInputShapesOnly, shapeProfile, scalarInputMode in
        ONNXSessionHandle.placeholder(
            modelURL: url,
            preferredExecutionProvider: preferCoreML ? "CoreML Execution Provider" : "CPU fallback",
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode
        )
    }
    let repository = ORTModelRepository(baseRepository: baseRepository, sessionCache: cache)
    let installed = try await repository.installedModels()
    let modelID = try #require(installed.first?.id)

    try await repository.activateModel(id: modelID)
    let bootstrap = try await repository.bootstrapSession(for: modelID)
    let activated = try await repository.installedModels()

    #expect(activated.first?.loadState == .active)
    #expect(!bootstrap.isLiveSession)
    #expect(bootstrap.modeLabel == "cached")
}

@Test
func repositoryPreparesRuntimeSnapshotForUiConsumption() async throws {
    let bootstrap = try await RuntimeBootstrap.bootstrapDefault()
    let modelID = try #require(bootstrap.snapshot.installedModels.first?.id)

    let preparation = try await bootstrap.repository.prepareModelRuntime(for: modelID)

    #expect(preparation.model.id == modelID)
    #expect(!preparation.session.modelURL.path.isEmpty)
    #expect(preparation.session.isLiveSession)
    #expect(!preparation.inspection.inputNames.isEmpty)
    #expect(!preparation.inspection.outputNames.isEmpty)
    #expect(preparation.badges.count == 3)
    #expect(!preparation.displayTitle.isEmpty)
    #expect(!preparation.displaySubtitle.isEmpty)
}

@Test
func bootstrapExposesSpeechEngineThatTracksRepositoryState() async throws {
    let previousRemoteEnabled = UserDefaults.standard.object(forKey: RemoteAivisSpeechEngine.enabledUserDefaultsKey)
    let previousRemoteURL = UserDefaults.standard.object(forKey: RemoteAivisSpeechEngine.userDefaultsKey)
    UserDefaults.standard.removeObject(forKey: RemoteAivisSpeechEngine.enabledUserDefaultsKey)
    UserDefaults.standard.removeObject(forKey: RemoteAivisSpeechEngine.userDefaultsKey)
    defer {
        restoreUserDefaultsValue(previousRemoteEnabled, forKey: RemoteAivisSpeechEngine.enabledUserDefaultsKey)
        restoreUserDefaultsValue(previousRemoteURL, forKey: RemoteAivisSpeechEngine.userDefaultsKey)
    }

    let bootstrap = try await RuntimeBootstrap.bootstrapDefault()
    let modelID = try #require(bootstrap.snapshot.installedModels.first?.id)
    let installed = try await bootstrap.repository.installedModels()
    #expect(installed.contains(where: { $0.id == modelID && $0.loadState == .active }))

    let query = try await bootstrap.speechEngine.makeAudioQuery(text: "アクティブです", styleID: 0)
    #expect(!query.accentPhrases.isEmpty)

    do {
        let audio = try await bootstrap.speechEngine.synthesize(query: query, styleID: 0)
        #expect(String(decoding: audio.prefix(4), as: UTF8.self) == "RIFF")
    } catch let error as StyleBertVITS2SpeechEngineError {
        switch error {
        case .missingBERTAssets, .bertFeaturePipelineUnavailable, .sampleSeedModelCannotSynthesize:
            break
        default:
            Issue.record("Unexpected bootstrap speech engine error: \(error)")
        }
    } catch {
        Issue.record("Unexpected bootstrap speech engine error: \(error)")
    }
}

private func restoreUserDefaultsValue(_ value: Any?, forKey key: String) {
    if let value {
        UserDefaults.standard.set(value, forKey: key)
    } else {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
