import Foundation
import Testing
import AivisMobileCore
@testable import AivisSpeechRuntime

struct AdaptiveSpeechEngineTests {
    @Test
    func bundledBERTAssetsResolveFromModuleResources() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let assets = try #require(
            StyleBertVITS2SpeechEngine.AssetConfiguration(cacheDirectory: temporaryDirectory).resolvedAssets
        )

        #expect(FileManager.default.fileExists(atPath: assets.modelURL.path))
        #expect(FileManager.default.fileExists(atPath: assets.tokenizerURL.path))
    }

    @Test
    func realEngineReportsMissingBERTAssets() async throws {
        let bootstrap = try await RuntimeBootstrap.bootstrapDefault()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let engine = StyleBertVITS2SpeechEngine(
            modelRepository: bootstrap.repository,
            assetConfiguration: .init(cacheDirectory: temporaryDirectory)
        )
        if engineAssetFallbackIsAvailable(cacheDirectory: temporaryDirectory) {
            return
        }

        let query = try await engine.makeAudioQuery(text: "実エンジン確認", styleID: 0)

        do {
            _ = try await engine.synthesize(query: query, styleID: 0)
            Issue.record("Expected StyleBertVITS2SpeechEngine to fail without BERT assets.")
        } catch let error as StyleBertVITS2SpeechEngineError {
            switch error {
            case let .bertFeaturePipelineUnavailable(requiredInputs):
                #expect(requiredInputs.contains("bert"))
            case let .missingBERTAssets(cacheDirectory):
                #expect(cacheDirectory == temporaryDirectory)
            default:
                Issue.record("Expected missingBERTAssets or bertFeaturePipelineUnavailable, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func engineAssetFallbackIsAvailable(cacheDirectory: URL) -> Bool {
        StyleBertVITS2SpeechEngine.AssetConfiguration(cacheDirectory: cacheDirectory).resolvedAssets != nil
    }

    @Test
    func adaptiveEngineReportsRealEngineFailure() async throws {
        let bootstrap = try await RuntimeBootstrap.bootstrapDefault()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let adaptive = AdaptiveSpeechEngine(primary: StyleBertVITS2SpeechEngine(
            modelRepository: bootstrap.repository,
            assetConfiguration: .init(cacheDirectory: temporaryDirectory)
        ))

        if engineAssetFallbackIsAvailable(cacheDirectory: temporaryDirectory) {
            return
        }

        let query = try await adaptive.makeAudioQuery(text: "エラー確認", styleID: 0)
        do {
            _ = try await adaptive.synthesize(query: query, styleID: 0)
            Issue.record("Expected AdaptiveSpeechEngine to surface the real engine error.")
        } catch let error as StyleBertVITS2SpeechEngineError {
            switch error {
            case let .bertFeaturePipelineUnavailable(requiredInputs):
                #expect(requiredInputs.contains("bert"))
            case let .missingBERTAssets(cacheDirectory):
                #expect(cacheDirectory == temporaryDirectory)
            default:
                Issue.record("Expected missingBERTAssets or bertFeaturePipelineUnavailable, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
