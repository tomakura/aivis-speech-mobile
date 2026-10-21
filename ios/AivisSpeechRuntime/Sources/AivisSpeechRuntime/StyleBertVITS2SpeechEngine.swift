import Foundation
import AivisMobileCore

public enum StyleBertVITS2SpeechEngineError: LocalizedError {
    case emptyText
    case noActiveModel
    case missingModelFile
    case missingModelMetadata
    case unsupportedModelArchitecture(String)
    case unsupportedStyle(styleID: Int, modelName: String)
    case missingBERTAssets(cacheDirectory: URL)
    case bertFeaturePipelineUnavailable(requiredInputs: [String])
    case sampleSeedModelCannotSynthesize(modelName: String)
    case acousticInferenceFailed(String)
    case unsupportedFrontendText([String])
    case unsupportedInputContract([String])
    case unsupportedInputSignature(inputNames: [String], outputNames: [String])
    case frontendPipelineUnavailable
    case nativeSynthesisInputTooLong(actualPhonemes: Int, maxPhonemes: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Enter text before building an audio query."
        case .noActiveModel:
            return "Activate a Style-Bert-VITS2 model before synthesizing speech."
        case .missingModelFile:
            return "The active model is missing its local AIVMX file."
        case .missingModelMetadata:
            return "The active model metadata is incomplete."
        case let .unsupportedModelArchitecture(architecture):
            return "Model architecture \(architecture) is not supported by the native Style-Bert-VITS2 engine."
        case let .unsupportedStyle(styleID, modelName):
            return "Style \(styleID) is not available on active model \(modelName)."
        case let .missingBERTAssets(cacheDirectory):
            return "BERT assets are not installed at \(cacheDirectory.path)."
        case let .bertFeaturePipelineUnavailable(requiredInputs):
            return "The BERT feature pipeline is not wired yet for inputs: \(requiredInputs.joined(separator: ", "))."
        case let .sampleSeedModelCannotSynthesize(modelName):
            return "\(modelName) is a bundled runtime seed model, not a real Style-Bert-VITS2 voice model. Import a real AIVMX model before synthesizing."
        case let .acousticInferenceFailed(message):
            return "Style-Bert-VITS2 acoustic inference failed: \(message)"
        case let .unsupportedFrontendText(characters):
            return "端末内の日本語フロントエンドに OpenJTalk がまだ統合されていないため読みを推定できません: \(characters.joined(separator: " ")). リモートエンジンでの代替は単体動作ではないため、正式対応には iOS ネイティブ OpenJTalk 統合が必要です。"
        case let .unsupportedInputContract(requiredInputs):
            return "Model inputs are not supported yet: \(requiredInputs.joined(separator: ", "))."
        case let .unsupportedInputSignature(inputNames, outputNames):
            let joinedInputs = inputNames.joined(separator: ", ")
            let joinedOutputs = outputNames.joined(separator: ", ")
            return "Model signature is not wired yet. Inputs: \(joinedInputs) Outputs: \(joinedOutputs)."
        case .frontendPipelineUnavailable:
            return "The Style-Bert-VITS2 frontend pipeline is not complete yet."
        case let .nativeSynthesisInputTooLong(actualPhonemes, maxPhonemes):
            return "入力が長すぎるため端末内合成を中止しました。phonemes=\(actualPhonemes), limit=\(maxPhonemes)。文章を短く分けてください。"
        }
    }
}

public struct StyleBertVITS2SpeechEngine: SpeechEngine {
    private static let maxChunkMoras = 48
    private static let maxChunkPhonemes = 320
    private static let maxChunkBERTTokens = 160

    public struct AssetConfiguration: Sendable {
        public var cacheDirectory: URL
        public var modelFilename: String
        public var tokenizerFilename: String

        public init(
            cacheDirectory: URL,
            modelFilename: String = "model_fp16.onnx",
            tokenizerFilename: String = "tokenizer.json"
        ) {
            self.cacheDirectory = cacheDirectory
            self.modelFilename = modelFilename
            self.tokenizerFilename = tokenizerFilename
        }

        public var modelURL: URL {
            cacheDirectory.appendingPathComponent(modelFilename)
        }

        public var tokenizerURL: URL {
            cacheDirectory.appendingPathComponent(tokenizerFilename)
        }
    }

    private let modelRepository: any ModelRepository
    private let assetConfiguration: AssetConfiguration

    public init(
        modelRepository: any ModelRepository,
        assetConfiguration: AssetConfiguration = .default
    ) {
        self.modelRepository = modelRepository
        self.assetConfiguration = assetConfiguration
    }

    public func supportedDevices() async throws -> SupportedDevices {
        ONNXRuntimeSupport.supportedDevices()
    }

    public func makeAudioQuery(text: String, styleID: Int) async throws -> AudioQuery {
        let activeModel = try await activeModel()
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw StyleBertVITS2SpeechEngineError.emptyText
        }
        try validate(styleID: styleID, against: activeModel)

        let descriptor = activeModel.manifest?.runtimeDescriptor
        let hyper = descriptor?.hyperParameters
        let accentPhrases = try OpenJTalkFrontend.accentPhrases(
            from: normalizedText,
            styleID: styleID,
            userDictionary: SharedUserDictionaryStorage.load() ?? UserDictionary(entries: [])
        )
        let query = AudioQuery(
            accentPhrases: accentPhrases,
            speedScale: hyper?.speedScale ?? 1.0,
            intonationScale: hyper?.intonationScale ?? 1.0,
            tempoDynamicsScale: hyper?.tempoDynamicsScale ?? 1.0,
            pitchScale: hyper?.pitchScale ?? 0.0,
            volumeScale: hyper?.volumeScale ?? 1.0,
            pauseLengthScale: hyper?.pauseLengthScale ?? 1.0,
            prePhonemeLength: hyper?.prePhonemeLength ?? 0.1,
            postPhonemeLength: hyper?.postPhonemeLength ?? 0.1,
            outputSamplingRate: hyper?.outputSamplingRate.map(OutputSamplingRate.explicit) ?? .explicit(44_100),
            outputStereo: hyper?.outputStereo ?? false,
            kana: normalizedText
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
        try ensureSupportedArchitecture(for: activeModel)
        guard let localFileURL = activeModel.localFileURL else {
            throw StyleBertVITS2SpeechEngineError.missingModelFile
        }
        guard let bertAssets = assetConfiguration.resolvedAssets else {
            throw StyleBertVITS2SpeechEngineError.missingBERTAssets(cacheDirectory: assetConfiguration.cacheDirectory)
        }

        let inspection = try ONNXRuntimeSupport.inspectModel(
            at: localFileURL,
            preferCoreML: false
        )
        let contract = StyleBertVITS2InputContract(inspection: inspection)
        if contract.isSampleSeedContract {
            throw StyleBertVITS2SpeechEngineError.sampleSeedModelCannotSynthesize(modelName: activeModel.name)
        }

        guard contract.canBuildTensorPlan else {
            throw StyleBertVITS2SpeechEngineError.unsupportedInputContract(contract.unresolvedRequiredInputNames)
        }
        if !contract.unresolvedRequiredInputNames.isEmpty {
            throw StyleBertVITS2SpeechEngineError.unsupportedInputContract(contract.unresolvedRequiredInputNames)
        }

        let plan = try StyleBertVITS2TensorPlanner.makePlan(
            query: query,
            styleID: styleID,
            activeModel: activeModel
        )
        if shouldSynthesizeInChunks(plan) {
            return try await synthesizeChunked(query: query, styleID: styleID)
        }

        return try synthesizeSingleQuery(
            query: query,
            styleID: styleID,
            activeModel: activeModel,
            localFileURL: localFileURL,
            inspection: inspection,
            contract: contract,
            plan: plan,
            bertAssets: bertAssets
        )
    }

    private func synthesizeSingleQuery(
        query: AudioQuery,
        styleID: Int,
        activeModel: InstalledModel,
        localFileURL: URL,
        inspection: ONNXModelInspection,
        contract: StyleBertVITS2InputContract,
        plan: StyleBertVITS2TensorPlan,
        bertAssets: BERTSessionAssets
    ) throws -> Data {
        let acousticShapeProfile = BucketedShapePlanner.acousticProfile(
            forPhonemeCount: plan.phonemeCount,
            styleVectorDimension: plan.styleVectorDimension
        )
        let features = try StyleBertVITS2FeatureProvider.resolve(
            contract: contract,
            plan: plan,
            assetConfiguration: assetConfiguration
        )
        ONNXRuntimeSupport.sharedSessionCache.invalidateSessions(for: bertAssets.modelURL)
        if case let .unavailable(requiredInputs) = features {
            throw StyleBertVITS2SpeechEngineError.bertFeaturePipelineUnavailable(requiredInputs: requiredInputs)
        }

        let inputs = try StyleBertVITS2TensorBuilder.makeInputs(
            contract: contract,
            plan: plan,
            featureResolution: features
        )
        let outputName = contract.preferredWaveformOutputName ?? inspection.outputNames.first
        guard let outputName else {
            throw StyleBertVITS2SpeechEngineError.unsupportedInputSignature(
                inputNames: inspection.inputNames,
                outputNames: inspection.outputNames
            )
        }

        let outputs: [String: ONNXTensorValue]
        do {
            outputs = try ONNXModelRunner.run(
                modelURL: localFileURL,
                inputs: inputs,
                outputNames: [outputName],
                preferCoreML: true,
                staticInputShapesOnly: true,
                shapeProfile: acousticShapeProfile
            )
        } catch {
            throw StyleBertVITS2SpeechEngineError.acousticInferenceFailed(error.localizedDescription)
        }
        guard let waveform = outputs[outputName] else {
            throw StyleBertVITS2SpeechEngineError.unsupportedInputSignature(
                inputNames: inspection.inputNames,
                outputNames: inspection.outputNames
            )
        }
        return try InferenceWAVWriter.makeWAVData(
            from: waveform,
            sampleRate: plan.outputSampleRate,
            stereo: query.outputStereo
        )
    }

    private func shouldSynthesizeInChunks(_ plan: StyleBertVITS2TensorPlan) -> Bool {
        plan.phonemeCount > Self.maxChunkPhonemes
            || plan.wordToPhonemeCounts.count > Self.maxChunkBERTTokens
    }

    private func synthesizeChunked(query: AudioQuery, styleID: Int) async throws -> Data {
        let chunks = Self.chunkedQueries(from: query, maxMoras: Self.maxChunkMoras)
        guard chunks.count > 1 else {
            let activeModel = try await activeModel()
            let plan = try StyleBertVITS2TensorPlanner.makePlan(
                query: query,
                styleID: styleID,
                activeModel: activeModel
            )
            throw StyleBertVITS2SpeechEngineError.nativeSynthesisInputTooLong(
                actualPhonemes: plan.phonemeCount,
                maxPhonemes: Self.maxChunkPhonemes
            )
        }

        var wavs: [Data] = []
        wavs.reserveCapacity(chunks.count)
        for chunk in chunks {
            wavs.append(try await synthesize(query: chunk, styleID: styleID))
        }
        return try InferenceWAVWriter.concatenateWAVData(wavs)
    }

    private func activeModel() async throws -> InstalledModel {
        let models = try await modelRepository.installedModels()
        guard let model = models.first(where: { $0.loadState == .active }) else {
            throw StyleBertVITS2SpeechEngineError.noActiveModel
        }
        return model
    }

    private func validate(styleID: Int, against model: InstalledModel) throws {
        guard let manifest = model.manifest else {
            throw StyleBertVITS2SpeechEngineError.missingModelMetadata
        }
        let allStyleIDs = manifest.runtimeDescriptor?.availableStyleIDs
            ?? manifest.speakers.flatMap(\.styles).map(\.localID)
        guard allStyleIDs.contains(styleID) else {
            throw StyleBertVITS2SpeechEngineError.unsupportedStyle(styleID: styleID, modelName: model.name)
        }
    }

    private func ensureSupportedArchitecture(for model: InstalledModel) throws {
        guard let architecture = model.manifest?.modelArchitecture else {
            throw StyleBertVITS2SpeechEngineError.missingModelMetadata
        }
        guard architecture == AIVMXModelArchitecture.styleBertVITS2.rawValue
            || architecture == AIVMXModelArchitecture.styleBertVITS2JPExtra.rawValue else {
            throw StyleBertVITS2SpeechEngineError.unsupportedModelArchitecture(architecture)
        }
    }

    private static func chunkedQueries(from query: AudioQuery, maxMoras: Int) -> [AudioQuery] {
        var chunks: [[AccentPhrase]] = []
        var current: [AccentPhrase] = []
        var currentMoraCount = 0

        for phrase in query.accentPhrases.flatMap({ splitPhrase($0, maxMoras: maxMoras) }) {
            let phraseMoraCount = phrase.moras.count + (phrase.pauseMora == nil ? 0 : 1)
            if !current.isEmpty, currentMoraCount + phraseMoraCount > maxMoras {
                chunks.append(current)
                current = []
                currentMoraCount = 0
            }
            current.append(phrase)
            currentMoraCount += phraseMoraCount
        }
        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks.map { phrases in
            var chunk = query
            chunk.accentPhrases = phrases
            chunk.kana = phrases.map { phrase in
                phrase.moras.map(\.text).joined() + (phrase.pauseMora == nil ? "" : "、")
            }.joined()
            return chunk
        }
    }

    private static func splitPhrase(_ phrase: AccentPhrase, maxMoras: Int) -> [AccentPhrase] {
        guard phrase.moras.count > maxMoras, maxMoras > 0 else {
            return [phrase]
        }

        var result: [AccentPhrase] = []
        var start = phrase.moras.startIndex
        while start < phrase.moras.endIndex {
            let end = min(start + maxMoras, phrase.moras.endIndex)
            let moras = Array(phrase.moras[start..<end])
            let localAccent = phrase.accent > start && phrase.accent <= end
                ? phrase.accent - start
                : min(1, moras.count)
            result.append(AccentPhrase(
                moras: moras,
                accent: max(1, localAccent),
                pauseMora: end == phrase.moras.endIndex ? phrase.pauseMora : nil,
                isInterrogative: end == phrase.moras.endIndex ? phrase.isInterrogative : nil
            ))
            start = end
        }
        return result
    }

}

public extension StyleBertVITS2SpeechEngine.AssetConfiguration {
    static var `default`: Self {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return Self(
            cacheDirectory: appSupportURL
                .appendingPathComponent("AivisSpeechMobile", isDirectory: true)
                .appendingPathComponent("BertModelCaches", isDirectory: true)
        )
    }
}
