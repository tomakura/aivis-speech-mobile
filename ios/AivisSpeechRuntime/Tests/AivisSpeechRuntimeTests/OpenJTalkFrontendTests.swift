import Foundation
import Testing
@testable import AivisSpeechRuntime
import AivisMobileCore

@Test
func openJTalkFrontendReadsKanjiMixedTextOnDevicePath() throws {
    let nodes = try OpenJTalkFrontend.analyze(text: "今日はテストです。")

    #expect(nodes.contains { $0.surface == "今日" && $0.pronunciation.contains("キョ") })
    #expect(nodes.map(\.pronunciation).joined().contains("テ"))
}

@Test
func openJTalkFrontendBuildsAccentPhrasesForKanjiMixedText() throws {
    let phrases = try OpenJTalkFrontend.accentPhrases(from: "今日はテストです。", styleID: 0)
    let moraTexts = phrases.flatMap(\.moras).map(\.text).joined()

    #expect(!phrases.isEmpty)
    #expect(phrases.count >= 4)
    #expect(moraTexts.contains("キョ"))
    #expect(moraTexts.contains("テ"))
    #expect(phrases.contains { $0.pauseMora?.vowel == "pau" })
}

@Test
func openJTalkFrontendKeepsGreetingAccentNatural() throws {
    let phrases = try OpenJTalkFrontend.accentPhrases(from: "こんにちは", styleID: 0)
    let phrase = try #require(phrases.first)

    #expect(phrase.moras.map(\.text).joined() == "コンニチワ")
    #expect(phrase.accent == phrase.moras.count)
}

@Test
func openJTalkFrontendKeepsStandaloneVowelsAsVowels() throws {
    for (text, expected) in [
        ("あ", ["ア"]),
        ("お", ["オ"]),
        ("あお", ["ア", "オ"]),
        ("ああ", ["ア", "ア"]),
        ("おお", ["オ", "オ"]),
        ("あ、お。", ["ア", "オ"]),
    ] {
        let phrases = try OpenJTalkFrontend.accentPhrases(from: text, styleID: 0)
        let moras = phrases.flatMap(\.moras)

        #expect(moras.map(\.text) == expected)
        #expect(!moras.map(\.text).contains("ー"))
    }
}

@Test
func openJTalkFrontendKeepsExplicitLongVowelMarks() throws {
    let phrases = try OpenJTalkFrontend.accentPhrases(from: "あー", styleID: 0)
    let moras = phrases.flatMap(\.moras)

    #expect(moras.map(\.text) == ["ア", "ー"])
}

@Test
func openJTalkFrontendAppliesUserDictionaryEntries() throws {
    let dictionary = UserDictionary(
        entries: [
            UserDictionaryEntry(
                id: UUID(),
                surface: "琴葉",
                pronunciation: "コトハ",
                accentType: 2,
                wordType: .properNoun,
                priority: 10
            )
        ]
    )

    let phrases = try OpenJTalkFrontend.accentPhrases(
        from: "琴葉です。",
        styleID: 0,
        userDictionary: dictionary
    )
    let firstPhrase = try #require(phrases.first)

    #expect(Array(firstPhrase.moras.prefix(3)).map(\.text) == ["コ", "ト", "ハ"])
    #expect(firstPhrase.accent == 2)
}

@Test
func dictionaryAwareAudioQueryReplacesKanaWithDictionaryPronunciation() throws {
    let storedDictionary = UserDictionary(
        entries: [
            UserDictionaryEntry(
                id: UUID(),
                surface: "琴葉",
                pronunciation: "コトハ",
                accentType: 2,
                wordType: .properNoun,
                priority: 10
            )
        ]
    )
    try SharedUserDictionaryStorage.save(storedDictionary)
    defer { SharedUserDictionaryStorage.clear() }

    let query = AudioQuery(
        accentPhrases: [],
        speedScale: 1.0,
        intonationScale: 1.0,
        tempoDynamicsScale: 1.0,
        pitchScale: 0.0,
        volumeScale: 1.0,
        pauseLengthScale: 1.0,
        prePhonemeLength: 0.1,
        postPhonemeLength: 0.1,
        outputSamplingRate: .explicit(44_100),
        outputStereo: false,
        kana: "琴葉です。"
    )

    let patched = DictionaryAwareAudioQuery.applySharedUserDictionary(
        to: query,
        text: "琴葉です。",
        styleID: 0
    )

    #expect(patched.kana == "コトハデス。")
    #expect(Array(patched.accentPhrases.first?.moras.prefix(3) ?? []).map(\.text) == ["コ", "ト", "ハ"])
}
