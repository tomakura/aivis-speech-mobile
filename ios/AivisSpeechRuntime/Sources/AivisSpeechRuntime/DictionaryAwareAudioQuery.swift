import Foundation
import AivisMobileCore

enum DictionaryAwareAudioQuery {
    static func applySharedUserDictionary(
        to query: AudioQuery,
        text: String,
        styleID: Int
    ) -> AudioQuery {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty,
              let dictionary = SharedUserDictionaryStorage.load(),
              !dictionary.entries.isEmpty,
              let accentPhrases = try? OpenJTalkFrontend.accentPhrases(
                from: normalizedText,
                styleID: styleID,
                userDictionary: dictionary
              ) else {
            return query
        }

        return AudioQuery(
            accentPhrases: accentPhrases,
            speedScale: query.speedScale,
            intonationScale: query.intonationScale,
            tempoDynamicsScale: query.tempoDynamicsScale,
            pitchScale: query.pitchScale,
            volumeScale: query.volumeScale,
            pauseLengthScale: query.pauseLengthScale,
            prePhonemeLength: query.prePhonemeLength,
            postPhonemeLength: query.postPhonemeLength,
            outputSamplingRate: query.outputSamplingRate,
            outputStereo: query.outputStereo,
            kana: kanaText(from: accentPhrases)
        )
    }

    private static func kanaText(from accentPhrases: [AccentPhrase]) -> String {
        accentPhrases.map { phrase in
            let moraText = phrase.moras.map(\.text).joined()
            if let pauseText = phrase.pauseMora?.text {
                return moraText + pauseText
            }
            return moraText
        }
        .joined()
    }
}
