import Foundation
import AivisMobileCore

struct StyleBertVITS2TensorPlan: Sendable, Equatable {
    let text: String
    let wordToPhonemeCounts: [Int]
    let phonemeSymbols: [String]
    let phonemeIDs: [Int64]
    let tones: [Int64]
    let languageIDs: [Int64]
    let phonemeCount: Int
    let speakerID: Int64
    let styleID: Int64
    let styleVector: [Float]
    let styleVectorDimension: Int
    let lengthScale: Float
    let sdpRatio: Float
    let noiseScale: Float
    let noiseScaleW: Float
    let outputSampleRate: Int
}

enum StyleBertVITS2TensorPlanError: LocalizedError {
    case missingRuntimeDescriptor
    case missingSpeakerForStyle(Int)
    case invalidPhoneme(String)

    var errorDescription: String? {
        switch self {
        case .missingRuntimeDescriptor:
            return "The active model is missing runtime descriptor metadata."
        case let .missingSpeakerForStyle(styleID):
            return "No speaker/style mapping was found for style \(styleID)."
        case let .invalidPhoneme(phoneme):
            return "Unsupported phoneme \(phoneme) in tensor plan."
        }
    }
}

enum StyleBertVITS2TensorPlanner {
    private struct Segment {
        let text: String
        let phones: [String]
        let rawTone: Int
    }

    private struct ProsodyPlan {
        let text: String
        let phones: [String]
        let tones: [Int]
        let wordToPhonemeCounts: [Int]
    }

    private static let symbolToID: [String: Int64] = {
        let symbols = [
            "_", "AA", "E", "EE", "En", "N", "OO", "V", "a", "a:", "aa", "ae",
            "ah", "ai", "an", "ang", "ao", "aw", "ay", "b", "by", "c", "ch",
            "d", "dh", "dy", "e", "e:", "eh", "ei", "en", "eng", "er", "ey",
            "f", "g", "gy", "h", "hh", "hy", "i", "i0", "i:", "ia", "ian",
            "iang", "iao", "ie", "ih", "in", "ing", "iong", "ir", "iu", "iy",
            "j", "jh", "k", "ky", "l", "m", "my", "n", "ng", "ny", "o", "o:",
            "ong", "ou", "ow", "oy", "p", "py", "q", "r", "ry", "s", "sh", "t",
            "th", "ts", "ty", "u", "u:", "ua", "uai", "uan", "uang", "uh", "ui",
            "un", "uo", "uw", "v", "van", "ve", "vn", "w", "x", "y", "z", "zh",
            "zy", "!", "?", "…", ",", ".", "'", "-", "SP", "UNK",
        ]
        return Dictionary(uniqueKeysWithValues: symbols.enumerated().map { (offset, symbol) in
            (symbol, Int64(offset))
        })
    }()
    private static let japaneseToneStart: Int64 = 6
    private static let japaneseLanguageID: Int64 = 1
    private static let defaultSDPRatio: Float = 0.2
    private static let defaultNoiseScale: Float = 0.6
    private static let defaultNoiseScaleW: Float = 0.8
    private static let addBlank = true

    static func makePlan(
        query: AudioQuery,
        styleID: Int,
        activeModel: InstalledModel
    ) throws -> StyleBertVITS2TensorPlan {
        guard let manifest = activeModel.manifest,
              let runtimeDescriptor = manifest.runtimeDescriptor else {
            throw StyleBertVITS2TensorPlanError.missingRuntimeDescriptor
        }

        let prosody = try makeProsodyPlan(from: query)
        let speakerID = try resolveSpeakerID(for: styleID, manifest: manifest)
        let vectorDimension = resolveStyleVectorDimension(styleID: styleID, descriptor: runtimeDescriptor)
        let styleVector = AIVMXStyleVectorResolver.resolveVector(
            styleID: styleID,
            modelURL: activeModel.localFileURL,
            manifest: manifest,
            expectedDimension: vectorDimension
        ) ?? Array(repeating: Float.zero, count: vectorDimension)

        var phonemeSymbols = prosody.phones
        var tones = scaledTones(prosody.tones, intonationScale: query.intonationScale)
            .map { Int64($0) + japaneseToneStart }
        var languageIDs = Array(repeating: japaneseLanguageID, count: phonemeSymbols.count)
        var wordToPhonemeCounts = prosody.wordToPhonemeCounts

        if addBlank {
            phonemeSymbols = intersperse(phonemeSymbols, with: "_")
            tones = intersperse(tones, with: 0)
            languageIDs = intersperse(languageIDs, with: 0)
            wordToPhonemeCounts = wordToPhonemeCounts.map { $0 * 2 }
            wordToPhonemeCounts[0] += 1
        }

        let phonemeIDs = try phonemeSymbols.map { phoneme in
            guard let id = symbolToID[phoneme] else {
                throw StyleBertVITS2TensorPlanError.invalidPhoneme(phoneme)
            }
            return id
        }

        return StyleBertVITS2TensorPlan(
            text: prosody.text,
            wordToPhonemeCounts: wordToPhonemeCounts,
            phonemeSymbols: phonemeSymbols,
            phonemeIDs: phonemeIDs,
            tones: tones,
            languageIDs: languageIDs,
            phonemeCount: phonemeIDs.count,
            speakerID: Int64(speakerID),
            styleID: Int64(styleID),
            styleVector: styleVector,
            styleVectorDimension: styleVector.count,
            lengthScale: Float(1.0 / max(0.1, query.speedScale)),
            sdpRatio: resolveSDPRatio(from: query.tempoDynamicsScale),
            noiseScale: defaultNoiseScale,
            noiseScaleW: defaultNoiseScaleW,
            outputSampleRate: resolveSampleRate(query.outputSamplingRate, descriptor: runtimeDescriptor)
        )
    }

    private static func makeProsodyPlan(from query: AudioQuery) throws -> ProsodyPlan {
        let text = query.kana?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? query.accentPhrases.flatMap(\.moras).map(\.text).joined()
        if query.accentPhrases.isEmpty {
            let g2p = try OpenJTalkFrontend.g2p(text: text)
            return ProsodyPlan(
                text: g2p.text,
                phones: g2p.phones,
                tones: g2p.tones,
                wordToPhonemeCounts: g2p.wordToPhonemeCounts
            )
        }

        let segments = buildSegments(from: query)
        let phones = segments.flatMap(\.phones)
        let tones = segments.flatMap { segment in
            Array(repeating: segment.rawTone, count: segment.phones.count)
        }
        let bertText = text.isEmpty ? segments.map(\.text).joined() : text
        let wordToPhonemeCounts = [1]
            + distributePhone(phones.count, across: max(1, bertText.count))
            + [1]

        return ProsodyPlan(
            text: bertText,
            phones: ["_"] + phones + ["_"],
            tones: [0] + tones + [0],
            wordToPhonemeCounts: wordToPhonemeCounts
        )
    }

    private static func buildSegments(from query: AudioQuery) -> [Segment] {
        var segments: [Segment] = []
        var previousVowel: String?

        for phrase in query.accentPhrases {
            let accentIndex = max(0, phrase.accent - 1)

            for index in phrase.moras.indices {
                let rawTone: Int
                if index == 0 && accentIndex != 0 {
                    rawTone = 0
                } else if index <= accentIndex {
                    rawTone = 1
                } else {
                    rawTone = 0
                }

                let phones = phones(for: phrase.moras[index], previousVowel: previousVowel)
                if let last = phones.last, !isPunctuationPhone(last) {
                    previousVowel = last
                }
                segments.append(
                    Segment(
                        text: normalizedTokenizerText(phrase.moras[index].text),
                        phones: phones,
                        rawTone: rawTone
                    )
                )
            }

            if let pause = phrase.pauseMora {
                let phone = punctuationPhone(from: pause.text)
                previousVowel = nil
                segments.append(
                    Segment(
                        text: normalizedTokenizerText(pause.text),
                        phones: [phone],
                        rawTone: 0
                    )
                )
            }
        }

        return segments
    }

    private static func phones(for mora: Mora, previousVowel: String?) -> [String] {
        if let punctuation = punctuationPhoneIfAvailable(from: mora.text) {
            return [punctuation]
        }

        if mora.text == "ー" {
            return [longVowelPhone(from: previousVowel)]
        }

        var phones: [String] = []
        if let consonant = mora.consonant {
            phones.append(normalizedPhoneme(consonant))
        }
        phones.append(normalizedPhoneme(mora.vowel))
        return phones
    }

    private static func normalizedPhoneme(_ raw: String) -> String {
        switch raw {
        case "sil":
            return "SP"
        case "pau":
            return "SP"
        case "cl":
            return "q"
        case "j":
            return "j"
        case "-":
            return "o:"
        default:
            return raw
        }
    }

    private static func longVowelPhone(from previousVowel: String?) -> String {
        guard let previousVowel else {
            return "o:"
        }
        switch previousVowel {
        case "a", "a:":
            return "a:"
        case "e", "e:":
            return "e:"
        case "i", "i:":
            return "i:"
        case "o", "o:":
            return "o:"
        case "u", "u:":
            return "u:"
        default:
            return "o:"
        }
    }

    private static func normalizedTokenizerText(_ raw: String) -> String {
        var normalized = ""
        normalized.reserveCapacity(raw.count)

        for scalar in raw.unicodeScalars {
            switch scalar.value {
            case 0x3041 ... 0x3096:
                if let converted = UnicodeScalar(scalar.value + 0x60) {
                    normalized.unicodeScalars.append(converted)
                }
            default:
                normalized.unicodeScalars.append(scalar)
            }
        }

        return punctuationPhoneIfAvailable(from: normalized) ?? normalized
    }

    private static func punctuationPhone(from text: String) -> String {
        punctuationPhoneIfAvailable(from: text) ?? ","
    }

    private static func punctuationPhoneIfAvailable(from text: String) -> String? {
        switch text {
        case "、", ",":
            return ","
        case "。", ".":
            return "."
        case "！", "!":
            return "!"
        case "？", "?":
            return "?"
        case "…":
            return "…"
        case "'", "「", "」", "（", "）", "(", ")":
            return "'"
        case "-", "―", "‐", "−":
            return "-"
        default:
            return nil
        }
    }

    private static func isPunctuationPhone(_ phone: String) -> Bool {
        [",", ".", "!", "?", "…", "'", "-", "SP"].contains(phone)
    }

    private static func intersperse<T>(_ values: [T], with separator: T) -> [T] {
        guard !values.isEmpty else { return [] }
        var result = Array(repeating: separator, count: values.count * 2 + 1)
        for (index, value) in values.enumerated() {
            result[index * 2 + 1] = value
        }
        return result
    }

    private static func distributePhone(_ phoneCount: Int, across characterCount: Int) -> [Int] {
        guard characterCount > 0 else { return [] }
        var phonesPerCharacter = Array(repeating: 0, count: characterCount)
        for _ in 0..<phoneCount {
            let minimum = phonesPerCharacter.min() ?? 0
            if let index = phonesPerCharacter.firstIndex(of: minimum) {
                phonesPerCharacter[index] += 1
            }
        }
        return phonesPerCharacter
    }

    private static func resolveSpeakerID(for styleID: Int, manifest: ModelManifest) throws -> Int {
        for (speakerIndex, speaker) in manifest.speakers.enumerated() {
            if speaker.styles.contains(where: { $0.localID == styleID }) {
                return speakerIndex
            }
        }
        throw StyleBertVITS2TensorPlanError.missingSpeakerForStyle(styleID)
    }

    private static func resolveStyleVectorDimension(
        styleID: Int,
        descriptor: ModelRuntimeDescriptor
    ) -> Int {
        if let styleDimension = descriptor.styleProfiles.first(where: { $0.localID == styleID })?.vectorDimension {
            return styleDimension
        }
        if let vectorDimension = descriptor.vectorProfiles.first(where: { $0.associatedStyleIDs.contains(styleID) })?.dimension {
            return vectorDimension
        }
        return 256
    }

    private static func resolveSampleRate(
        _ outputSamplingRate: OutputSamplingRate,
        descriptor: ModelRuntimeDescriptor
    ) -> Int {
        switch outputSamplingRate {
        case .engineDefault:
            return max(8_000, descriptor.hyperParameters.outputSamplingRate ?? 44_100)
        case let .explicit(value):
            return max(8_000, value)
        }
    }

    private static func resolveSDPRatio(from scale: Double?) -> Float {
        let normalized = min(max(scale ?? 1.0, 0.0), 2.0)
        if normalized <= 1.0 {
            return Float(normalized) * defaultSDPRatio
        }
        return defaultSDPRatio + Float(normalized - 1.0) * (1.0 - defaultSDPRatio)
    }

    private static func scaledTones(_ tones: [Int], intonationScale: Double) -> [Int] {
        guard !tones.isEmpty else {
            return tones
        }
        let scale = min(max(intonationScale, 0.0), 3.0)
        guard scale != 1.0 else {
            return tones
        }
        if scale <= 0.0 {
            return tones.map { _ in 0 }
        }
        if scale < 1.0 {
            return tones.enumerated().map { index, tone in
                guard tone > 0 else { return 0 }
                let slot = Double(index % 8) / 7.0
                return slot <= scale ? tone : 0
            }
        }

        return tones.indices.map { index in
            let tone = tones[index]
            guard tone == 0 else { return tone }
            let radius = max(1, Int((scale - 1.0).rounded(.up)))
            let searchRange = max(tones.startIndex, index - radius)...min(tones.index(before: tones.endIndex), index + radius)
            let hasHighNeighbor = searchRange.contains { tones[$0] > 0 }
            guard hasHighNeighbor else { return tone }
            let slot = Double(index % 8) / 7.0
            return slot <= min(1.0, scale - 1.0) ? 1 : tone
        }
    }
}
