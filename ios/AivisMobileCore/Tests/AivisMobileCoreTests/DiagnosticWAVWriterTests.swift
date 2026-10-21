import Foundation
import Testing
@testable import AivisMobileCore

struct DiagnosticWAVWriterTests {
    @Test
    func createsValidRiffHeader() throws {
        let query = Self.query(text: "あ")

        let data = try DiagnosticWAVWriter.makeWAVData(from: query, text: "あ")
        #expect(data.count > 44)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: data[12..<16], as: UTF8.self) == "fmt ")
        #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")
    }

    @Test
    func concatenatesMatchingWAVData() throws {
        let first = try DiagnosticWAVWriter.makeWAVData(from: Self.query(text: "一行目"), text: "一行目")
        let second = try DiagnosticWAVWriter.makeWAVData(from: Self.query(text: "二行目"), text: "二行目")

        let concatenated = try WAVDataConcatenator.concatenate([first, second])

        #expect(String(decoding: concatenated.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: concatenated[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: concatenated[36..<40], as: UTF8.self) == "data")
        #expect(concatenated.count == first.count + second.count - 44)
    }

    @Test
    func rejectsEmptyWAVConcatenationInput() throws {
        #expect(throws: WAVConcatenationError.emptyInput) {
            try WAVDataConcatenator.concatenate([])
        }
    }

    @Test
    func rejectsMismatchedWAVFormats() throws {
        let mono = try DiagnosticWAVWriter.makeWAVData(from: Self.query(text: "mono", stereo: false), text: "mono")
        let stereo = try DiagnosticWAVWriter.makeWAVData(from: Self.query(text: "stereo", stereo: true), text: "stereo")

        #expect(throws: WAVConcatenationError.self) {
            try WAVDataConcatenator.concatenate([mono, stereo])
        }
    }

    private static func query(text: String, stereo: Bool = false) -> AudioQuery {
        AudioQuery(
            accentPhrases: [
                AccentPhrase(
                    moras: [Mora(text: text, vowel: "a", vowelLength: 0.18, pitch: 1.0)],
                    accent: 1
                )
            ],
            speedScale: 1.0,
            intonationScale: 1.0,
            tempoDynamicsScale: 1.0,
            pitchScale: 0.0,
            volumeScale: 1.0,
            pauseLengthScale: 1.0,
            prePhonemeLength: 0.1,
            postPhonemeLength: 0.1,
            outputSamplingRate: .explicit(44_100),
            outputStereo: stereo,
            kana: text
        )
    }
}
