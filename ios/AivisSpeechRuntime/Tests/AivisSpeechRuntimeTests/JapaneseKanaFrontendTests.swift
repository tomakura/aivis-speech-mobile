import Testing
@testable import AivisSpeechRuntime

@Test
func kanaFrontendGroupsPhrasesAndPauses() {
    let phrases = JapaneseKanaFrontend.accentPhrases(from: "こんにちは、アイビスです。", styleID: 12)

    #expect(phrases.count == 2)
    #expect(phrases.first?.moras.isEmpty == false)
    #expect(phrases.first?.pauseMora?.vowel == "pau")
    #expect(phrases.last?.moras.last?.text == "ス")
}

@Test
func kanaFrontendAcceptsHiraganaAndDigraphs() {
    let phrases = JapaneseKanaFrontend.accentPhrases(from: "きょうはびょういん", styleID: 4)
    let moras = phrases.flatMap(\.moras)

    #expect(moras.map(\.text).contains("キョ"))
    #expect(moras.map(\.text).contains("ビョ"))
}

@Test
func kanaFrontendKeepsStandaloneVowelsAsVowels() {
    let moras = JapaneseKanaFrontend.moras(from: "あお", styleID: 0)

    #expect(moras.map(\.text) == ["ア", "オ"])
    #expect(moras.map(\.vowel) == ["a", "o"])
}

@Test
func kanaFrontendReportsUnsupportedKanjiInsteadOfMappingToA() {
    let unsupported = JapaneseKanaFrontend.unsupportedCharacters(in: "今日はテストです")

    #expect(unsupported.contains("今"))
    #expect(unsupported.contains("日"))
    #expect(!unsupported.contains("テ"))
}
