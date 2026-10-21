import Foundation
import Testing
@testable import AivisSpeechRuntime

struct BERTTokenizerTests {
    private static let tokenizerURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("vendor/Style-Bert-VITS2/bert/deberta-v2-large-japanese-char-wwm-onnx/tokenizer.json")

    @Test
    func tokenizerBuildsExpectedIDsForJapaneseCharacters() throws {
        let tokenizer = try BERTTokenizerJSON(contentsOf: Self.tokenizerURL)

        let sequence = tokenizer.encode("こんにちは")

        #expect(sequence.inputIDs == [1, 37, 57, 8, 105, 18, 2])
        #expect(sequence.attentionMask == [1, 1, 1, 1, 1, 1, 1])
        #expect(sequence.tokenTypeIDs == [0, 0, 0, 0, 0, 0, 0])
    }

    @Test
    func tokenizerMapsUnknownCharactersToUNK() throws {
        let tokenizer = try BERTTokenizerJSON(contentsOf: Self.tokenizerURL)

        let sequence = tokenizer.encode("🧌")

        #expect(sequence.inputIDs == [1, 3, 2])
    }
}
