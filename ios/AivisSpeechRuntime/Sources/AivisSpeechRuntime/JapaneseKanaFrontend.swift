import Foundation
import AivisMobileCore

enum JapaneseKanaFrontend {
    private static let punctuation = Set(["、", "。", "！", "？", ",", ".", "!", "?"])
    private static let pausePunctuation = Set(["、", "。", ",", "."])
    private static let comboTable: [String: (String?, String)] = [
        "キャ": ("ky", "a"), "キュ": ("ky", "u"), "キョ": ("ky", "o"),
        "シャ": ("sh", "a"), "シュ": ("sh", "u"), "ショ": ("sh", "o"),
        "チャ": ("ch", "a"), "チュ": ("ch", "u"), "チョ": ("ch", "o"),
        "ニャ": ("ny", "a"), "ニュ": ("ny", "u"), "ニョ": ("ny", "o"),
        "ヒャ": ("hy", "a"), "ヒュ": ("hy", "u"), "ヒョ": ("hy", "o"),
        "ミャ": ("my", "a"), "ミュ": ("my", "u"), "ミョ": ("my", "o"),
        "リャ": ("ry", "a"), "リュ": ("ry", "u"), "リョ": ("ry", "o"),
        "ギャ": ("gy", "a"), "ギュ": ("gy", "u"), "ギョ": ("gy", "o"),
        "ジャ": ("j", "a"), "ジュ": ("j", "u"), "ジョ": ("j", "o"),
        "ビャ": ("by", "a"), "ビュ": ("by", "u"), "ビョ": ("by", "o"),
        "ピャ": ("py", "a"), "ピュ": ("py", "u"), "ピョ": ("py", "o"),
    ]
    private static let moraTable: [String: (String?, String)] = [
        "ア": (nil, "a"), "イ": (nil, "i"), "ウ": (nil, "u"), "エ": (nil, "e"), "オ": (nil, "o"),
        "カ": ("k", "a"), "キ": ("k", "i"), "ク": ("k", "u"), "ケ": ("k", "e"), "コ": ("k", "o"),
        "サ": ("s", "a"), "シ": ("sh", "i"), "ス": ("s", "u"), "セ": ("s", "e"), "ソ": ("s", "o"),
        "タ": ("t", "a"), "チ": ("ch", "i"), "ツ": ("ts", "u"), "テ": ("t", "e"), "ト": ("t", "o"),
        "ナ": ("n", "a"), "ニ": ("n", "i"), "ヌ": ("n", "u"), "ネ": ("n", "e"), "ノ": ("n", "o"),
        "ハ": ("h", "a"), "ヒ": ("h", "i"), "フ": ("f", "u"), "ヘ": ("h", "e"), "ホ": ("h", "o"),
        "マ": ("m", "a"), "ミ": ("m", "i"), "ム": ("m", "u"), "メ": ("m", "e"), "モ": ("m", "o"),
        "ヤ": ("y", "a"), "ユ": ("y", "u"), "ヨ": ("y", "o"),
        "ラ": ("r", "a"), "リ": ("r", "i"), "ル": ("r", "u"), "レ": ("r", "e"), "ロ": ("r", "o"),
        "ワ": ("w", "a"), "ヲ": (nil, "o"), "ン": (nil, "N"),
        "ガ": ("g", "a"), "ギ": ("g", "i"), "グ": ("g", "u"), "ゲ": ("g", "e"), "ゴ": ("g", "o"),
        "ザ": ("z", "a"), "ジ": ("j", "i"), "ズ": ("z", "u"), "ゼ": ("z", "e"), "ゾ": ("z", "o"),
        "ダ": ("d", "a"), "ヂ": ("j", "i"), "ヅ": ("z", "u"), "デ": ("d", "e"), "ド": ("d", "o"),
        "バ": ("b", "a"), "ビ": ("b", "i"), "ブ": ("b", "u"), "ベ": ("b", "e"), "ボ": ("b", "o"),
        "パ": ("p", "a"), "ピ": ("p", "i"), "プ": ("p", "u"), "ペ": ("p", "e"), "ポ": ("p", "o"),
        "ァ": (nil, "a"), "ィ": (nil, "i"), "ゥ": (nil, "u"), "ェ": (nil, "e"), "ォ": (nil, "o"),
        "ー": (nil, "-"), "ッ": (nil, "cl"),
    ]

    static func accentPhrases(from text: String, styleID: Int) -> [AccentPhrase] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else {
            return []
        }

        var phrases: [AccentPhrase] = []
        var currentMoras: [Mora] = []

        func flushPhrase(withPause pause: Mora?) {
            guard !currentMoras.isEmpty else { return }
            let accent = max(1, min(currentMoras.count, Int(ceil(Double(currentMoras.count) * 0.55))))
            phrases.append(AccentPhrase(moras: currentMoras, accent: accent, pauseMora: pause))
            currentMoras = []
        }

        var index = normalized.startIndex
        while index < normalized.endIndex {
            let character = String(normalized[index])

            if punctuation.contains(character) {
                let pause = pausePunctuation.contains(character)
                    ? Mora(text: character, consonant: nil, consonantLength: nil, vowel: "pau", vowelLength: 0.10, pitch: 0.0)
                    : nil
                flushPhrase(withPause: pause)
                index = normalized.index(after: index)
                continue
            }

            if let nextIndex = normalized.index(index, offsetBy: 1, limitedBy: normalized.endIndex),
               nextIndex < normalized.endIndex {
                let combo = String(normalized[index...nextIndex])
                if let phoneme = comboTable[combo] {
                    currentMoras.append(makeMora(text: combo, phoneme: phoneme, styleID: styleID, offset: currentMoras.count))
                    index = normalized.index(after: nextIndex)
                    continue
                }
            }

            if let phoneme = moraTable[character] {
                currentMoras.append(makeMora(text: character, phoneme: phoneme, styleID: styleID, offset: currentMoras.count))
            } else if !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentMoras.append(
                    Mora(
                        text: character,
                        consonant: nil,
                        consonantLength: nil,
                        vowel: "a",
                        vowelLength: 0.12,
                        pitch: 1.0 + Double((styleID + currentMoras.count) % 4) * 0.05
                    )
                )
            }

            index = normalized.index(after: index)
        }

        flushPhrase(withPause: nil)
        return phrases
    }

    static func moras(from text: String, styleID: Int, startingOffset: Int = 0) -> [Mora] {
        let normalized = normalize(text)
        var moras: [Mora] = []

        var index = normalized.startIndex
        while index < normalized.endIndex {
            let character = String(normalized[index])
            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || punctuation.contains(character) {
                index = normalized.index(after: index)
                continue
            }

            if let nextIndex = normalized.index(index, offsetBy: 1, limitedBy: normalized.endIndex),
               nextIndex < normalized.endIndex {
                let combo = String(normalized[index...nextIndex])
                if let phoneme = comboTable[combo] {
                    moras.append(makeMora(text: combo, phoneme: phoneme, styleID: styleID, offset: startingOffset + moras.count))
                    index = normalized.index(after: nextIndex)
                    continue
                }
            }

            if let phoneme = moraTable[character] {
                moras.append(makeMora(text: character, phoneme: phoneme, styleID: styleID, offset: startingOffset + moras.count))
            }
            index = normalized.index(after: index)
        }

        return moras
    }

    static func unsupportedCharacters(in text: String) -> [String] {
        let normalized = normalize(text)
        var unsupported: [String] = []

        var index = normalized.startIndex
        while index < normalized.endIndex {
            let character = String(normalized[index])

            if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || punctuation.contains(character) {
                index = normalized.index(after: index)
                continue
            }

            if let nextIndex = normalized.index(index, offsetBy: 1, limitedBy: normalized.endIndex),
               nextIndex < normalized.endIndex,
               comboTable[String(normalized[index...nextIndex])] != nil {
                index = normalized.index(after: nextIndex)
                continue
            }

            if moraTable[character] == nil, !unsupported.contains(character) {
                unsupported.append(character)
            }

            index = normalized.index(after: index)
        }

        return unsupported
    }

    private static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalized = ""
        normalized.reserveCapacity(trimmed.count)

        for scalar in trimmed.unicodeScalars {
            switch scalar.value {
            case 0x3041 ... 0x3096:
                if let converted = UnicodeScalar(scalar.value + 0x60) {
                    normalized.unicodeScalars.append(converted)
                }
            default:
                normalized.unicodeScalars.append(scalar)
            }
        }

        return normalized
    }

    private static func makeMora(
        text: String,
        phoneme: (String?, String),
        styleID: Int,
        offset: Int
    ) -> Mora {
        let vowel = phoneme.1 == "-" ? "o" : phoneme.1
        let basePitch = 1.0 + Double((abs(styleID) + offset) % 5) * 0.06

        return Mora(
            text: text,
            consonant: phoneme.0,
            consonantLength: phoneme.0 == nil ? nil : 0.04,
            vowel: vowel,
            vowelLength: phoneme.1 == "cl" ? 0.08 : 0.12,
            pitch: phoneme.1 == "pau" || phoneme.1 == "cl" ? 0.0 : basePitch
        )
    }
}
