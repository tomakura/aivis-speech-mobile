import Foundation
import AivisMobileCore

public enum WaveformPreviewSpeechEngineError: LocalizedError {
    case emptyText
    case noActiveModel
    case unsupportedStyle(styleID: Int, modelName: String)
    case missingModelMetadata

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Enter text before building an audio query."
        case .noActiveModel:
            return "Activate a model before synthesizing speech."
        case let .unsupportedStyle(styleID, modelName):
            return "Style \(styleID) is not available on active model \(modelName)."
        case .missingModelMetadata:
            return "Active model metadata is incomplete."
        }
    }
}

public struct WaveformPreviewSpeechEngine: SpeechEngine {
    private let modelRepository: (any ModelRepository)

    public init(modelRepository: any ModelRepository) {
        self.modelRepository = modelRepository
    }

    public func supportedDevices() async throws -> SupportedDevices {
        ONNXRuntimeSupport.supportedDevices()
    }

    public func makeAudioQuery(text: String, styleID: Int) async throws -> AudioQuery {
        let activeModel = try await activeModel()
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw WaveformPreviewSpeechEngineError.emptyText
        }
        try validate(styleID: styleID, against: activeModel)

        let styleSeed = styleID &+ Self.modelSeed(for: activeModel)
        let runtimeProfile = activeModel.manifest?.runtimeDescriptor?.styleProfiles.first(where: { $0.localID == styleID })

        let query = AudioQuery(
            accentPhrases: JapaneseKanaFrontend.accentPhrases(from: normalizedText, styleID: styleSeed),
            speedScale: 1.0,
            intonationScale: 1.0,
            tempoDynamicsScale: 1.0,
            pitchScale: 0.0,
            volumeScale: 1.0,
            pauseLengthScale: 1.0,
            prePhonemeLength: 0.1,
            postPhonemeLength: 0.1,
            outputSamplingRate: .explicit(activeModel.manifest?.runtimeDescriptor?.hyperParameters.outputSamplingRate ?? 44_100),
            outputStereo: activeModel.manifest?.runtimeDescriptor?.hyperParameters.outputStereo ?? false,
            kana: [normalizedText, runtimeProfile?.name].compactMap { $0 }.joined(separator: " · ")
        )

        return DictionaryAwareAudioQuery.applySharedUserDictionary(
            to: query,
            text: normalizedText,
            styleID: styleID
        )
    }

    public func synthesize(query: AudioQuery, styleID: Int) async throws -> Data {
        let activeModel = try await activeModel()
        try validate(styleID: styleID, against: activeModel)
        let effectiveQuery = applyRuntimeDescriptor(query, activeModel: activeModel, styleID: styleID)

        return try DiagnosticWAVWriter.makeWAVData(
            from: effectiveQuery,
            text: Self.renderingText(for: effectiveQuery, activeModel: activeModel),
            sampleRate: resolvedSampleRate(for: effectiveQuery.outputSamplingRate)
        )
    }

    private func activeModel() async throws -> InstalledModel {
        let models = try await modelRepository.installedModels()
        guard let model = models.first(where: { $0.loadState == .active }) else {
            throw WaveformPreviewSpeechEngineError.noActiveModel
        }
        return model
    }

    private func validate(styleID: Int, against model: InstalledModel) throws {
        guard let manifest = model.manifest else {
            throw WaveformPreviewSpeechEngineError.missingModelMetadata
        }

        let allStyleIDs = manifest.runtimeDescriptor?.availableStyleIDs
            ?? manifest.speakers.flatMap(\.styles).map(\.localID)
        guard allStyleIDs.contains(styleID) else {
            throw WaveformPreviewSpeechEngineError.unsupportedStyle(styleID: styleID, modelName: model.name)
        }
    }

    private func applyRuntimeDescriptor(
        _ query: AudioQuery,
        activeModel: InstalledModel,
        styleID: Int
    ) -> AudioQuery {
        guard let descriptor = activeModel.manifest?.runtimeDescriptor else {
            return query
        }

        let styleProfile = descriptor.styleProfiles.first(where: { $0.localID == styleID })
        let hyper = descriptor.hyperParameters

        return AudioQuery(
            accentPhrases: query.accentPhrases,
            speedScale: hyper.speedScale ?? query.speedScale,
            intonationScale: hyper.intonationScale ?? query.intonationScale,
            tempoDynamicsScale: hyper.tempoDynamicsScale ?? query.tempoDynamicsScale,
            pitchScale: hyper.pitchScale ?? query.pitchScale,
            volumeScale: hyper.volumeScale ?? query.volumeScale,
            pauseLengthScale: hyper.pauseLengthScale ?? query.pauseLengthScale,
            prePhonemeLength: hyper.prePhonemeLength ?? query.prePhonemeLength,
            postPhonemeLength: hyper.postPhonemeLength ?? query.postPhonemeLength,
            outputSamplingRate: hyper.outputSamplingRate.map(OutputSamplingRate.explicit) ?? query.outputSamplingRate,
            outputStereo: hyper.outputStereo ?? query.outputStereo,
            kana: query.kana ?? styleProfile?.name ?? query.accentPhrases.flatMap(\.moras).map(\.text).joined()
        )
    }

    private func resolvedSampleRate(for outputSamplingRate: OutputSamplingRate) -> Int {
        switch outputSamplingRate {
        case .engineDefault:
            return 44_100
        case let .explicit(value):
            return max(8_000, value)
        }
    }

    private static func modelSeed(for model: InstalledModel) -> Int {
        let source = [
            model.id.uuidString,
            model.name,
            model.version,
            model.loadState.rawValue,
            model.manifest?.runtimeDescriptor?.styleProfiles.map(\.name).joined(separator: ",") ?? "",
            model.manifest?.runtimeDescriptor?.vectorProfiles.map(\.key).joined(separator: ",") ?? "",
            model.manifest?.runtimeDescriptor?.notes.joined(separator: ",") ?? ""
        ].joined(separator: "|")
        return source.unicodeScalars.reduce(0) { partial, scalar in
            partial &+ Int(scalar.value)
        }
    }

    private static func renderingText(for query: AudioQuery, activeModel: InstalledModel) -> String {
        let queryText = query.kana?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? query.accentPhrases.flatMap(\.moras).map(\.text).joined()
        let descriptorSummary = activeModel.manifest?.runtimeDescriptor.map { descriptor in
            let styleSummary = descriptor.styleProfiles.map { "\($0.localID):\($0.name)" }.joined(separator: ",")
            let vectorSummary = descriptor.vectorProfiles.map { "\($0.key)=\($0.dimension)" }.joined(separator: ",")
            return [styleSummary, vectorSummary].filter { $0.isEmpty == false }.joined(separator: " | ")
        }
        return [
            activeModel.name,
            activeModel.version,
            descriptorSummary?.isEmpty == false ? descriptorSummary : nil,
            queryText
        ].compactMap { $0 }.joined(separator: " | ")
    }
}
