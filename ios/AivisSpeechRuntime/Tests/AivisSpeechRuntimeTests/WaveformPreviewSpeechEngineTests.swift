import Testing
import Foundation
import AivisMobileCore
@testable import AivisSpeechRuntime

@Test
func previewSpeechEngineBuildsAudioQuery() async throws {
    let bootstrap = try await RuntimeBootstrap.bootstrapDefault()
    let engine = WaveformPreviewSpeechEngine(modelRepository: bootstrap.repository)

    let query = try await engine.makeAudioQuery(text: "こんにちは Aivis", styleID: 0)

    #expect(!query.accentPhrases.isEmpty)
    #expect(query.kana?.hasPrefix("こんにちは Aivis") == true)
    #expect(query.accentPhrases.flatMap(\.moras).isEmpty == false)
}

@Test
func previewSpeechEngineSynthesizesRiffWaveform() async throws {
    let bootstrap = try await RuntimeBootstrap.bootstrapDefault()
    let engine = WaveformPreviewSpeechEngine(modelRepository: bootstrap.repository)
    let query = try await engine.makeAudioQuery(text: "プレビューです", styleID: 0)

    let data = try await engine.synthesize(query: query, styleID: 0)

    #expect(data.count > 44)
    #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
    #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
}

@Test
func previewSpeechEngineReflectsActiveModelState() async throws {
    let activeModelA = InstalledModel(
        id: UUID(),
        name: "Reference A",
        version: "1.0.0",
        loadState: .active,
        manifest: testManifest(name: "Reference A", hyperParameters: ModelHyperParameterMetadata(volumeScale: 1.0))
    )
    let activeModelB = InstalledModel(
        id: UUID(),
        name: "Reference B",
        version: "1.0.0",
        loadState: .active,
        manifest: testManifest(name: "Reference B", hyperParameters: ModelHyperParameterMetadata(volumeScale: 0.25))
    )

    let engineA = WaveformPreviewSpeechEngine(modelRepository: SingleModelRepository(model: activeModelA))
    let engineB = WaveformPreviewSpeechEngine(modelRepository: SingleModelRepository(model: activeModelB))

    let queryA = try await engineA.makeAudioQuery(text: "同じ入力", styleID: 0)
    let queryB = try await engineB.makeAudioQuery(text: "同じ入力", styleID: 0)

    let dataA = try await engineA.synthesize(query: queryA, styleID: 0)
    let dataB = try await engineB.synthesize(query: queryB, styleID: 0)

    #expect(dataA != dataB)
}

@Test
func previewSpeechEngineFailsWithoutActiveModel() async throws {
    let repository = EmptyRepository()
    let engine = WaveformPreviewSpeechEngine(modelRepository: repository)

    do {
        _ = try await engine.makeAudioQuery(text: "失敗するはず", styleID: 0)
        Issue.record("Expected makeAudioQuery to fail when no active model exists.")
    } catch let error as WaveformPreviewSpeechEngineError {
        switch error {
        case .noActiveModel:
            break
        default:
            Issue.record("Expected noActiveModel, got \(error)")
        }
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func previewSpeechEngineFailsSynthesisWithoutActiveModel() async throws {
    let repository = EmptyRepository()
    let engine = WaveformPreviewSpeechEngine(modelRepository: repository)
    let query = AudioQuery(
        accentPhrases: [],
        speedScale: 1.0,
        intonationScale: 1.0,
        tempoDynamicsScale: 1.0,
        pitchScale: 0.0,
        volumeScale: 1.0,
        pauseLengthScale: 1.0,
        prePhonemeLength: 0.1,
        postPhonemeLength: 0.1,
        outputSamplingRate: .explicit(44_100),
        outputStereo: false,
        kana: "失敗するはず"
    )

    do {
        _ = try await engine.synthesize(query: query, styleID: 0)
        Issue.record("Expected synthesize to fail when no active model exists.")
    } catch let error as WaveformPreviewSpeechEngineError {
        switch error {
        case .noActiveModel:
            break
        default:
            Issue.record("Expected noActiveModel, got \(error)")
        }
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private func testManifest(name: String, hyperParameters: ModelHyperParameterMetadata = ModelHyperParameterMetadata()) -> ModelManifest {
    ModelManifest(
        uuid: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
        name: name,
        version: "1.0.0",
        modelArchitecture: "Style-Bert-VITS2",
        modelFormat: "AIVMX",
        speakers: [
            ModelSpeaker(
                uuid: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
                name: "Speaker",
                styles: [ModelStyle(localID: 0, name: "Normal")]
            )
        ],
        runtimeDescriptor: ModelRuntimeDescriptor(
            styleProfiles: [
                ModelStyleRuntimeMetadata(localID: 0, name: "Normal", vectorDimension: 256, notes: ["Synthetic runtime descriptor"])
            ],
            vectorProfiles: [
                ModelVectorRuntimeMetadata(key: "speaker_embedding", dimension: 256, associatedStyleIDs: [0], notes: ["Synthetic vector profile"])
            ],
            hyperParameters: hyperParameters,
            notes: ["Synthetic runtime descriptor for testing"]
        )
    )
}

private actor SingleModelRepository: ModelRepository {
    let model: InstalledModel

    init(model: InstalledModel) {
        self.model = model
    }

    func installedModels() async throws -> [InstalledModel] {
        [model]
    }

    func installModel(fromFile fileURL: URL) async throws -> InstalledModel {
        throw ModelRepositoryError.invalidSource(fileURL)
    }

    func installModel(fromRemote remoteURL: URL) async throws -> InstalledModel {
        throw ModelRepositoryError.installFailed(remoteURL)
    }

    func updateModel(id: UUID) async throws -> InstalledModel {
        throw ModelRepositoryError.modelNotFound(id)
    }

    func loadModel(id: UUID) async throws {}
    func activateModel(id: UUID) async throws {}
    func unloadModel(id: UUID) async throws {}
    func removeModel(id: UUID) async throws {}
}

private actor EmptyRepository: ModelRepository {
    func installedModels() async throws -> [InstalledModel] {
        []
    }

    func installModel(fromFile fileURL: URL) async throws -> InstalledModel {
        throw ModelRepositoryError.invalidSource(fileURL)
    }

    func installModel(fromRemote remoteURL: URL) async throws -> InstalledModel {
        throw ModelRepositoryError.installFailed(remoteURL)
    }

    func updateModel(id: UUID) async throws -> InstalledModel {
        throw ModelRepositoryError.modelNotFound(id)
    }

    func loadModel(id: UUID) async throws {}
    func activateModel(id: UUID) async throws {}
    func unloadModel(id: UUID) async throws {}
    func removeModel(id: UUID) async throws {}
}
