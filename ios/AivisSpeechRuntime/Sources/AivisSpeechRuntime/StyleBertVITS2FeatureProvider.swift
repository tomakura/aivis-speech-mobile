import Foundation

enum StyleBertVITS2FeatureProvider {
    enum Resolution: Sendable, Equatable {
        case ready([String: ONNXTensorValue])
        case unavailable(requiredInputs: [String])
    }

    static func resolve(
        contract: StyleBertVITS2InputContract,
        plan: StyleBertVITS2TensorPlan,
        assetConfiguration: StyleBertVITS2SpeechEngine.AssetConfiguration
    ) throws -> Resolution {
        let bertInputs = [
            contract.bertInputName,
            contract.japaneseBertInputName,
            contract.englishBertInputName,
        ].compactMap { $0 }
        guard !bertInputs.isEmpty else {
            return .ready([:])
        }
        guard let assets = assetConfiguration.resolvedAssets else {
            return .unavailable(requiredInputs: bertInputs)
        }

        let japaneseFeatures = try BERTFeatureProvider.japanesePhoneLevelFeatures(
            text: plan.text,
            wordToPhonemeCounts: plan.wordToPhonemeCounts,
            assets: assets
        )

        var payload: [String: ONNXTensorValue] = [:]
        if let name = contract.japaneseBertInputName {
            payload[name] = japaneseFeatures
        } else if let name = contract.bertInputName {
            payload[name] = japaneseFeatures
        }

        let hiddenSize = japaneseFeatures.shape.dropFirst().first ?? 1024
        let zeroTensor = ONNXTensorValue.float32(
            Array(repeating: 0, count: hiddenSize * plan.phonemeCount),
            shape: [1, hiddenSize, plan.phonemeCount]
        )

        if contract.japaneseBertInputName != nil, let name = contract.bertInputName {
            payload[name] = zeroTensor
        }
        if let name = contract.englishBertInputName {
            payload[name] = zeroTensor
        }

        return .ready(payload)
    }
}
