import Foundation
import Testing
import AivisMobileCore
@testable import AivisSpeechRuntime

struct StyleBertVITS2IntegrationTests {
    @Test
    func synthesizesWaveDataWithLocalAIVMXAndDesktopBertCache() async throws {
        let engineSupportURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AivisSpeech-Engine")
        let modelURL = engineSupportURL
            .appendingPathComponent("Models/51cf5e96-f94f-4d50-a8d1-dbe540525161.aivmx")
        let bertCacheURL = engineSupportURL
            .appendingPathComponent("BertModelCaches")
        guard FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: bertCacheURL.path) else {
            return
        }

        let repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = FileModelRepository(rootDirectory: repositoryRoot)
        let installedModel = try await repository.installModel(fromFile: modelURL)
        let styleID = installedModel.manifest?.speakers.first?.styles.first?.localID ?? 0
        try await repository.activateModel(id: installedModel.id)

        let engine = StyleBertVITS2SpeechEngine(
            modelRepository: repository,
            assetConfiguration: .init(cacheDirectory: bertCacheURL)
        )

        let query = try await engine.makeAudioQuery(text: "アイビスです。", styleID: styleID)
        let wav = try await engine.synthesize(query: query, styleID: styleID)

        #expect(wav.starts(with: Data("RIFF".utf8)))
        #expect(wav.count > 4_096)
    }
}
