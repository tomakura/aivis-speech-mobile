import Foundation
import Testing
@testable import AivisSpeechRuntime

struct BERTTokenizerTests {
    @Test
    func tokenizerBuildsExpectedIDsForJapaneseCharacters() throws {
        let tokenizerURL = URL(fileURLWithPath: "/Users/flow/Programs/aivis-speech-mobile/vendor/Style-Bert-VITS2/bert/deberta-v2-large-japanese-char-wwm-onnx/tokenizer.json")
        let tokenizer = try BERTTokenizerJSON(contentsOf: tokenizerURL)

        let sequence = tokenizer.encode("こんにちは")

        #expect(sequence.inputIDs == [1, 37, 57, 8, 105, 18, 2])
        #expect(sequence.attentionMask == [1, 1, 1, 1, 1, 1, 1])
        #expect(sequence.tokenTypeIDs == [0, 0, 0, 0, 0, 0, 0])
    }

    @Test
    func tokenizerMapsUnknownCharactersToUNK() throws {
        let tokenizerURL = URL(fileURLWithPath: "/Users/flow/Programs/aivis-speech-mobile/vendor/Style-Bert-VITS2/bert/deberta-v2-large-japanese-char-wwm-onnx/tokenizer.json")
        let tokenizer = try BERTTokenizerJSON(contentsOf: tokenizerURL)

        let sequence = tokenizer.encode("🧌")

        #expect(sequence.inputIDs == [1, 3, 2])
    }
}
