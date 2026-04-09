import Foundation

enum BERTFeatureProviderError: LocalizedError {
    case tokenAlignmentMismatch(expected: Int, actual: Int)
    case unsupportedModelOutputShape([Int])
    case unsupportedBERTInputs([String])
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case let .tokenAlignmentMismatch(expected, actual):
            return "Tokenizer/BERT alignment mismatch. Expected \(expected) tokens, got \(actual)."
        case let .unsupportedModelOutputShape(shape):
            return "Unsupported BERT output shape: \(shape)."
        case let .unsupportedBERTInputs(inputs):
            return "Unsupported BERT input signature: \(inputs.joined(separator: ", "))."
        case let .inferenceFailed(message):
            return "BERT inference failed: \(message)"
        }
    }
}

enum BERTFeatureProvider {
    static func japanesePhoneLevelFeatures(
        text: String,
        wordToPhonemeCounts: [Int],
        assets: BERTSessionAssets
    ) throws -> ONNXTensorValue {
        let tokenizer = try BERTTokenizerJSON(contentsOf: assets.tokenizerURL)
        let tokenSequence = tokenizer.encode(text)
        guard tokenSequence.inputIDs.count == wordToPhonemeCounts.count else {
            throw BERTFeatureProviderError.tokenAlignmentMismatch(
                expected: wordToPhonemeCounts.count,
                actual: tokenSequence.inputIDs.count
            )
        }

        let shapeProfile = BucketedShapePlanner.bertProfile(forTokenCount: tokenSequence.inputIDs.count)
        let handle = try ONNXRuntimeSupport.cachedSessionHandle(
            for: assets.modelURL,
            preferCoreML: false,
            staticInputShapesOnly: true,
            shapeProfile: shapeProfile
        )
        let inspection = try handle.inspectModel()
        var inputs: [String: ONNXTensorValue] = [:]
        for inputName in inspection.inputNames {
            switch inputName.lowercased() {
            case "input_ids":
                inputs[inputName] = .int64(
                    padded(
                        tokenSequence.inputIDs,
                        to: shapeProfile["sequence_length"] ?? tokenSequence.inputIDs.count,
                        fill: tokenizer.padTokenID
                    ),
                    shape: [1, shapeProfile["sequence_length"] ?? tokenSequence.inputIDs.count]
                )
            case "attention_mask":
                inputs[inputName] = .int64(
                    padded(
                        tokenSequence.attentionMask,
                        to: shapeProfile["sequence_length"] ?? tokenSequence.attentionMask.count,
                        fill: 0
                    ),
                    shape: [1, shapeProfile["sequence_length"] ?? tokenSequence.attentionMask.count]
                )
            case "token_type_ids":
                inputs[inputName] = .int64(
                    padded(
                        tokenSequence.tokenTypeIDs,
                        to: shapeProfile["sequence_length"] ?? tokenSequence.tokenTypeIDs.count,
                        fill: 0
                    ),
                    shape: [1, shapeProfile["sequence_length"] ?? tokenSequence.tokenTypeIDs.count]
                )
            default:
                throw BERTFeatureProviderError.unsupportedBERTInputs(inspection.inputNames)
            }
        }

        let outputName = inspection.outputNames.first ?? "output"
        let outputs: [String: ONNXTensorValue]
        do {
            outputs = try ONNXModelRunner.run(
                modelURL: assets.modelURL,
                inputs: inputs,
                outputNames: [outputName],
                preferCoreML: false,
                staticInputShapesOnly: true,
                shapeProfile: shapeProfile
            )
        } catch {
            throw BERTFeatureProviderError.inferenceFailed(error.localizedDescription)
        }
        guard case let .float32(values, shape)? = outputs[outputName] else {
            throw BERTFeatureProviderError.unsupportedModelOutputShape([])
        }

        let (sequenceLength, hiddenSize, flattenedValues) = try normalizedHiddenStates(
            values: values,
            shape: shape
        )
        guard sequenceLength >= tokenSequence.inputIDs.count else {
            throw BERTFeatureProviderError.tokenAlignmentMismatch(
                expected: tokenSequence.inputIDs.count,
                actual: sequenceLength
            )
        }
        let trimmedHiddenStates = trimHiddenStates(
            flattenedValues,
            fromSequenceLength: sequenceLength,
            toSequenceLength: tokenSequence.inputIDs.count,
            hiddenSize: hiddenSize
        )

        let phoneLevel = repeatHiddenStates(
            trimmedHiddenStates,
            sequenceLength: tokenSequence.inputIDs.count,
            hiddenSize: hiddenSize,
            wordToPhonemeCounts: wordToPhonemeCounts
        )
        let phoneCount = wordToPhonemeCounts.reduce(0, +)
        return .float32(phoneLevel, shape: [1, hiddenSize, phoneCount])
    }

    private static func normalizedHiddenStates(
        values: [Float],
        shape: [Int]
    ) throws -> (sequenceLength: Int, hiddenSize: Int, values: [Float]) {
        if shape.count == 2 {
            return (shape[0], shape[1], values)
        }
        if shape.count == 3, shape[0] == 1 {
            return (shape[1], shape[2], values)
        }
        throw BERTFeatureProviderError.unsupportedModelOutputShape(shape)
    }

    private static func repeatHiddenStates(
        _ hiddenStates: [Float],
        sequenceLength: Int,
        hiddenSize: Int,
        wordToPhonemeCounts: [Int]
    ) -> [Float] {
        let phoneCount = wordToPhonemeCounts.reduce(0, +)
        var features = Array(repeating: Float.zero, count: hiddenSize * phoneCount)
        var destinationOffset = 0

        for tokenIndex in 0..<sequenceLength {
            let sourceOffset = tokenIndex * hiddenSize
            let repetitions = wordToPhonemeCounts[tokenIndex]
            guard repetitions > 0 else { continue }

            for _ in 0..<repetitions {
                for hiddenIndex in 0..<hiddenSize {
                    features[hiddenIndex * phoneCount + destinationOffset] = hiddenStates[sourceOffset + hiddenIndex]
                }
                destinationOffset += 1
            }
        }

        return features
    }

    private static func trimHiddenStates(
        _ hiddenStates: [Float],
        fromSequenceLength sourceLength: Int,
        toSequenceLength targetLength: Int,
        hiddenSize: Int
    ) -> [Float] {
        guard targetLength < sourceLength else { return hiddenStates }
        let requiredCount = targetLength * hiddenSize
        return Array(hiddenStates.prefix(requiredCount))
    }

    private static func padded(
        _ values: [Int64],
        to targetLength: Int,
        fill: Int64
    ) -> [Int64] {
        guard targetLength > values.count else { return values }
        return values + Array(repeating: fill, count: targetLength - values.count)
    }
}
