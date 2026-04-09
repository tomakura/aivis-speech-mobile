import Foundation

struct BERTTokenSequence: Sendable, Equatable {
    let normalizedText: String
    let tokenStrings: [String]
    let inputIDs: [Int64]
    let attentionMask: [Int64]
    let tokenTypeIDs: [Int64]
}

enum BERTTokenizerError: LocalizedError {
    case invalidTokenizerJSON
    case unsupportedModelType(String)
    case missingVocabulary
    case missingSpecialToken(String)

    var errorDescription: String? {
        switch self {
        case .invalidTokenizerJSON:
            return "The tokenizer.json payload is not readable."
        case let .unsupportedModelType(modelType):
            return "Unsupported tokenizer model type: \(modelType)."
        case .missingVocabulary:
            return "The tokenizer vocabulary is missing."
        case let .missingSpecialToken(token):
            return "Missing tokenizer special token: \(token)."
        }
    }
}

struct BERTTokenizerJSON: Sendable {
    let vocabulary: [String: Int64]
    let clsTokenID: Int64
    let sepTokenID: Int64
    let unkTokenID: Int64
    let padTokenID: Int64
    let maskTokenID: Int64
    let maxLength: Int

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw BERTTokenizerError.invalidTokenizerJSON
        }
        guard let model = json["model"] as? [String: Any] else {
            throw BERTTokenizerError.invalidTokenizerJSON
        }
        let modelType = model["type"] as? String ?? "unknown"
        guard modelType == "WordPiece" else {
            throw BERTTokenizerError.unsupportedModelType(modelType)
        }
        guard let vocab = model["vocab"] as? [String: NSNumber] else {
            throw BERTTokenizerError.missingVocabulary
        }

        self.vocabulary = vocab.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = entry.value.int64Value
        }
        self.clsTokenID = try BERTTokenizerJSON.requiredTokenID("[CLS]", in: vocabulary)
        self.sepTokenID = try BERTTokenizerJSON.requiredTokenID("[SEP]", in: vocabulary)
        self.unkTokenID = try BERTTokenizerJSON.requiredTokenID("[UNK]", in: vocabulary)
        self.padTokenID = try BERTTokenizerJSON.requiredTokenID("[PAD]", in: vocabulary)
        self.maskTokenID = try BERTTokenizerJSON.requiredTokenID("[MASK]", in: vocabulary)
        self.maxLength = 512
    }

    func encode(_ text: String) -> BERTTokenSequence {
        let normalizedText = normalize(text)
        let tokenStrings = normalizedText.map { character -> String in
            if character.isWhitespace {
                return "▁"
            }
            return String(character)
        }

        let tokenIDs = tokenStrings.map { vocabulary[$0] ?? unkTokenID }
        let truncatedIDs = Array(tokenIDs.prefix(max(0, maxLength - 2)))
        let truncatedStrings = Array(tokenStrings.prefix(truncatedIDs.count))
        let inputIDs = [clsTokenID] + truncatedIDs + [sepTokenID]

        return BERTTokenSequence(
            normalizedText: String(truncatedStrings.joined()),
            tokenStrings: truncatedStrings,
            inputIDs: inputIDs,
            attentionMask: Array(repeating: 1, count: inputIDs.count),
            tokenTypeIDs: Array(repeating: 0, count: inputIDs.count)
        )
    }

    private func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalized = ""
        normalized.reserveCapacity(trimmed.count)

        for scalar in trimmed.precomposedStringWithCompatibilityMapping.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) {
                continue
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                normalized.append(" ")
            } else {
                normalized.unicodeScalars.append(scalar)
            }
        }

        return normalized
    }

    private static func requiredTokenID(
        _ token: String,
        in vocabulary: [String: Int64]
    ) throws -> Int64 {
        guard let value = vocabulary[token] else {
            throw BERTTokenizerError.missingSpecialToken(token)
        }
        return value
    }
}
