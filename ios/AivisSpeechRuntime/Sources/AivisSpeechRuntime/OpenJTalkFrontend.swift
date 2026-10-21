import Foundation
import AivisMobileCore
import COpenJTalk

enum OpenJTalkFrontendError: LocalizedError {
    case missingDictionary
    case initializationFailed(String)
    case analysisFailed(String)
    case emptyAnalysis

    var errorDescription: String? {
        switch self {
        case .missingDictionary:
            return "OpenJTalk dictionary is missing from the app bundle."
        case let .initializationFailed(message):
            return "OpenJTalk initialization failed: \(message)"
        case let .analysisFailed(message):
            return "OpenJTalk analysis failed: \(message)"
        case .emptyAnalysis:
            return "OpenJTalk returned no readable tokens."
        }
    }
}

struct OpenJTalkFrontendNode: Equatable {
    var surface: String
    var pronunciation: String
    var partOfSpeech: String
    var accent: Int
    var moraSize: Int
    var chainFlag: Int
}

struct OpenJTalkG2PResult: Equatable {
    var text: String
    var phones: [String]
    var tones: [Int]
    var wordToPhonemeCounts: [Int]
}

enum OpenJTalkFrontend {
    static func accentPhrases(
        from text: String,
        styleID: Int,
        userDictionary: UserDictionary = UserDictionary(entries: [])
    ) throws -> [AccentPhrase] {
        let (rawNodes, labels) = try analyzeAndMakeLabels(text: text)
        let nodes = applyingUserDictionary(userDictionary.entries, to: rawNodes)
        let phoneTone = try alignTones(
            phonesWithPunctuation: phonesWithPunctuation(from: nodes),
            phoneToneWithoutPunctuation: phoneToneWithoutPunctuation(from: labels)
        )
        let phrases = buildAccentPhrases(from: nodes, styleID: styleID, phoneTone: phoneTone)
        guard !phrases.isEmpty else {
            throw OpenJTalkFrontendError.emptyAnalysis
        }
        return phrases
    }

    static func g2p(text: String) throws -> OpenJTalkG2PResult {
        let (nodes, labels) = try analyzeAndMakeLabels(text: text)
        let phonesWithPunctuation = phonesWithPunctuation(from: nodes)
        let phoneToneWithoutPunctuation = phoneToneWithoutPunctuation(from: labels)
        let phoneTone = try alignTones(
            phonesWithPunctuation: phonesWithPunctuation,
            phoneToneWithoutPunctuation: phoneToneWithoutPunctuation
        )
        let normalizedText = nodes.map { normalizedSurface($0.surface) }.joined()
        let wordToPhonemeCounts = [1] + wordToPhonemeCounts(from: nodes) + [1]

        return OpenJTalkG2PResult(
            text: normalizedText,
            phones: ["_"] + phoneTone.map(\.phone) + ["_"],
            tones: [0] + phoneTone.map(\.tone) + [0],
            wordToPhonemeCounts: wordToPhonemeCounts
        )
    }

    static func analyze(text: String) throws -> [OpenJTalkFrontendNode] {
        let dictionaryURL = Bundle.module.url(forResource: "OpenJTalkDictionary", withExtension: nil)
            ?? Bundle.module.url(forResource: "sys", withExtension: "dic")?.deletingLastPathComponent()
        guard let dictionaryURL else {
            throw OpenJTalkFrontendError.missingDictionary
        }

        var errorBuffer = [CChar](repeating: 0, count: 512)
        let handle = try errorBuffer.withUnsafeMutableBufferPointer { buffer -> OpaquePointer in
            let pointer = copenjtalk_create(
                dictionaryURL.path,
                buffer.baseAddress,
                CInt(buffer.count)
            )
            guard let pointer else {
                throw OpenJTalkFrontendError.initializationFailed(String(cString: buffer.baseAddress!))
            }
            return pointer
        }
        defer {
            copenjtalk_destroy(handle)
        }

        var nodes: [OpenJTalkFrontendNode] = []
        let callback: COpenJTalkNodeCallback = { nodePointer, context in
            guard let nodePointer, let context else {
                return
            }
            let node = nodePointer.pointee
            let target = context.assumingMemoryBound(to: [OpenJTalkFrontendNode].self)
            target.pointee.append(
                OpenJTalkFrontendNode(
                    surface: node.surface.map(String.init(cString:)) ?? "",
                    pronunciation: node.pronunciation.map(String.init(cString:)) ?? "",
                    partOfSpeech: node.part_of_speech.map(String.init(cString:)) ?? "",
                    accent: Int(node.accent),
                    moraSize: Int(node.mora_size),
                    chainFlag: Int(node.chain_flag)
                )
            )
        }

        let succeeded = errorBuffer.withUnsafeMutableBufferPointer { buffer -> Bool in
            withUnsafeMutablePointer(to: &nodes) { nodeContext in
                copenjtalk_run_frontend(
                    handle,
                    text,
                    callback,
                    UnsafeMutableRawPointer(nodeContext),
                    buffer.baseAddress,
                    CInt(buffer.count)
                ) == 1
            }
        }
        guard succeeded else {
            throw OpenJTalkFrontendError.analysisFailed(errorMessage(from: errorBuffer))
        }

        return nodes
    }

    static func makeLabels(text: String) throws -> [String] {
        let dictionaryURL = Bundle.module.url(forResource: "OpenJTalkDictionary", withExtension: nil)
            ?? Bundle.module.url(forResource: "sys", withExtension: "dic")?.deletingLastPathComponent()
        guard let dictionaryURL else {
            throw OpenJTalkFrontendError.missingDictionary
        }

        var errorBuffer = [CChar](repeating: 0, count: 512)
        let handle = try errorBuffer.withUnsafeMutableBufferPointer { buffer -> OpaquePointer in
            let pointer = copenjtalk_create(
                dictionaryURL.path,
                buffer.baseAddress,
                CInt(buffer.count)
            )
            guard let pointer else {
                throw OpenJTalkFrontendError.initializationFailed(String(cString: buffer.baseAddress!))
            }
            return pointer
        }
        defer {
            copenjtalk_destroy(handle)
        }

        var labels: [String] = []
        let callback: COpenJTalkLabelCallback = { labelPointer, context in
            guard let labelPointer, let context else {
                return
            }
            let target = context.assumingMemoryBound(to: [String].self)
            target.pointee.append(String(cString: labelPointer))
        }
        let succeeded = errorBuffer.withUnsafeMutableBufferPointer { buffer -> Bool in
            withUnsafeMutablePointer(to: &labels) { labelContext in
                copenjtalk_make_labels(
                    handle,
                    text,
                    callback,
                    UnsafeMutableRawPointer(labelContext),
                    buffer.baseAddress,
                    CInt(buffer.count)
                ) == 1
            }
        }
        guard succeeded else {
            throw OpenJTalkFrontendError.analysisFailed(errorMessage(from: errorBuffer))
        }

        return labels
    }

    // Creates a single OpenJTalk handle and runs both frontend (analyze) and
    // label generation in one pass, avoiding the overhead of two create/destroy cycles.
    private static func analyzeAndMakeLabels(text: String) throws -> ([OpenJTalkFrontendNode], [String]) {
        let dictionaryURL = Bundle.module.url(forResource: "OpenJTalkDictionary", withExtension: nil)
            ?? Bundle.module.url(forResource: "sys", withExtension: "dic")?.deletingLastPathComponent()
        guard let dictionaryURL else {
            throw OpenJTalkFrontendError.missingDictionary
        }

        var errorBuffer = [CChar](repeating: 0, count: 512)
        let handle = try errorBuffer.withUnsafeMutableBufferPointer { buffer -> OpaquePointer in
            let pointer = copenjtalk_create(
                dictionaryURL.path,
                buffer.baseAddress,
                CInt(buffer.count)
            )
            guard let pointer else {
                throw OpenJTalkFrontendError.initializationFailed(String(cString: buffer.baseAddress!))
            }
            return pointer
        }
        defer {
            copenjtalk_destroy(handle)
        }

        var nodes: [OpenJTalkFrontendNode] = []
        let nodeCallback: COpenJTalkNodeCallback = { nodePointer, context in
            guard let nodePointer, let context else { return }
            let node = nodePointer.pointee
            let target = context.assumingMemoryBound(to: [OpenJTalkFrontendNode].self)
            target.pointee.append(
                OpenJTalkFrontendNode(
                    surface: node.surface.map(String.init(cString:)) ?? "",
                    pronunciation: node.pronunciation.map(String.init(cString:)) ?? "",
                    partOfSpeech: node.part_of_speech.map(String.init(cString:)) ?? "",
                    accent: Int(node.accent),
                    moraSize: Int(node.mora_size),
                    chainFlag: Int(node.chain_flag)
                )
            )
        }
        let frontendSucceeded = errorBuffer.withUnsafeMutableBufferPointer { buffer -> Bool in
            withUnsafeMutablePointer(to: &nodes) { ctx in
                copenjtalk_run_frontend(handle, text, nodeCallback, UnsafeMutableRawPointer(ctx),
                                        buffer.baseAddress, CInt(buffer.count)) == 1
            }
        }
        guard frontendSucceeded else {
            throw OpenJTalkFrontendError.analysisFailed(errorMessage(from: errorBuffer))
        }

        var labels: [String] = []
        let labelCallback: COpenJTalkLabelCallback = { labelPointer, context in
            guard let labelPointer, let context else { return }
            let target = context.assumingMemoryBound(to: [String].self)
            target.pointee.append(String(cString: labelPointer))
        }
        let labelsSucceeded = errorBuffer.withUnsafeMutableBufferPointer { buffer -> Bool in
            withUnsafeMutablePointer(to: &labels) { ctx in
                copenjtalk_make_labels(handle, text, labelCallback, UnsafeMutableRawPointer(ctx),
                                       buffer.baseAddress, CInt(buffer.count)) == 1
            }
        }
        guard labelsSucceeded else {
            throw OpenJTalkFrontendError.analysisFailed(errorMessage(from: errorBuffer))
        }

        return (nodes, labels)
    }

    private static func errorMessage(from buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard !bytes.isEmpty else {
            return "OpenJTalk error"
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func buildAccentPhrases(
        from nodes: [OpenJTalkFrontendNode],
        styleID: Int,
        phoneTone: [(phone: String, tone: Int)]
    ) -> [AccentPhrase] {
        var phrases: [AccentPhrase] = []
        var currentMoras: [Mora] = []
        var currentAccent = 1
        var phoneToneIndex = phoneTone.startIndex
        var previousVowel: String?

        func flush(pauseMora: Mora? = nil) {
            guard !currentMoras.isEmpty else {
                return
            }
            // accent=0 is valid for heiban (flat); do not clamp to min 1.
            phrases.append(
                AccentPhrase(
                    moras: currentMoras,
                    accent: min(max(0, currentAccent), currentMoras.count),
                    pauseMora: pauseMora
                )
            )
            currentMoras = []
            currentAccent = 1
        }

        for node in nodes {
            if let pause = pauseMora(for: node) {
                consumePunctuationTone(node, from: phoneTone, index: &phoneToneIndex)
                previousVowel = nil
                flush(pauseMora: pause)
                continue
            }

            let parsedMoras = JapaneseKanaFrontend.moras(
                from: node.pronunciation,
                styleID: styleID,
                startingOffset: currentMoras.count
            )
            let moras = morasByPreservingUserVowels(
                parsedMoras,
                for: node,
                styleID: styleID,
                startingOffset: currentMoras.count
            )
            guard !moras.isEmpty else {
                // No moras (e.g. brackets, hyphens with empty OpenJTalk pronunciation).
                // Consume any residual pause phone so phoneToneIndex stays aligned.
                consumePunctuationTone(node, from: phoneTone, index: &phoneToneIndex)
                continue
            }

            if !currentMoras.isEmpty {
                flush()
            }

            let moraTones = tonesForMoras(
                moras,
                from: phoneTone,
                index: &phoneToneIndex,
                previousVowel: &previousVowel
            )
            currentAccent = accentType(fromMoraTones: moraTones, fallback: node.accent)
            currentMoras.append(contentsOf: moras)
        }

        flush()
        return phrases
    }

    private static func applyingUserDictionary(
        _ entries: [UserDictionaryEntry],
        to nodes: [OpenJTalkFrontendNode]
    ) -> [OpenJTalkFrontendNode] {
        let candidates = entries
            .map { entry in
                (entry, normalizedSurface(entry.surface), katakana(entry.pronunciation))
            }
            .filter { !$0.1.isEmpty && !$0.2.isEmpty }
            .sorted {
                if $0.1.count == $1.1.count {
                    return $0.0.priority > $1.0.priority
                }
                return $0.1.count > $1.1.count
            }

        guard !candidates.isEmpty else {
            return nodes
        }

        var result: [OpenJTalkFrontendNode] = []
        var index = nodes.startIndex

        while index < nodes.endIndex {
            var matchedEntry: UserDictionaryEntry?
            var matchedNodeCount = 0

            for candidate in candidates {
                let (entry, targetSurface, normalizedPronunciation) = candidate
                var combinedSurface = ""
                var consumedCount = 0
                var cursor = index

                while cursor < nodes.endIndex {
                    let normalizedNodeSurface = normalizedSurface(nodes[cursor].surface)
                    if normalizedNodeSurface.isEmpty {
                        break
                    }

                    let nextSurface = combinedSurface + normalizedNodeSurface
                    guard targetSurface.hasPrefix(nextSurface) else {
                        break
                    }

                    combinedSurface = nextSurface
                    consumedCount += 1
                    cursor += 1

                    if combinedSurface == targetSurface {
                        matchedEntry = entry
                        matchedNodeCount = consumedCount
                        break
                    }
                }

                if matchedEntry != nil {
                    let moraCount = JapaneseKanaFrontend.moras(from: normalizedPronunciation, styleID: 0).count
                    guard moraCount > 0 else {
                        matchedEntry = nil
                        matchedNodeCount = 0
                        break
                    }
                    result.append(
                        OpenJTalkFrontendNode(
                            surface: entry.surface,
                            pronunciation: normalizedPronunciation,
                            partOfSpeech: partOfSpeech(for: entry.wordType),
                            accent: min(max(entry.accentType, 1), moraCount),
                            moraSize: moraCount,
                            chainFlag: 0
                        )
                    )
                    index += matchedNodeCount
                    break
                }
            }

            if matchedEntry == nil {
                result.append(nodes[index])
                index += 1
            }
        }

        return result
    }

    private static func morasByPreservingUserVowels(
        _ moras: [Mora],
        for node: OpenJTalkFrontendNode,
        styleID: Int,
        startingOffset: Int
    ) -> [Mora] {
        guard moras.contains(where: { $0.text == "ー" }) else {
            return moras
        }

        let surfaceMoras = JapaneseKanaFrontend.moras(
            from: node.surface,
            styleID: styleID,
            startingOffset: startingOffset
        )
        guard surfaceMoras.count == moras.count,
              !surfaceMoras.contains(where: { $0.text == "ー" }) else {
            return moras
        }

        return zip(moras, surfaceMoras).map { parsed, surface in
            guard parsed.text == "ー" else {
                return parsed
            }
            var mora = parsed
            mora.text = surface.text
            mora.consonant = surface.consonant
            mora.consonantLength = surface.consonantLength
            mora.vowel = surface.vowel
            return mora
        }
    }

    private static func tonesForMoras(
        _ moras: [Mora],
        from phoneTone: [(phone: String, tone: Int)],
        index: inout [(phone: String, tone: Int)].Index,
        previousVowel: inout String?
    ) -> [Int] {
        moras.map { mora in
            let phones = phones(for: mora, previousVowel: previousVowel)
            if let last = phones.last, !isPunctuationPhone(last) {
                previousVowel = last
            }

            var consumedTones: [Int] = []
            for phone in phones {
                guard index < phoneTone.endIndex else {
                    break
                }
                if phoneTone[index].phone == phone {
                    consumedTones.append(phoneTone[index].tone)
                    index = phoneTone.index(after: index)
                } else {
                    // Mismatch (including punctuation phones that don't belong to this mora):
                    // always advance to prevent permanent desync between mora list and label stream.
                    index = phoneTone.index(after: index)
                }
            }
            return consumedTones.last ?? 0
        }
    }

    private static func consumePunctuationTone(
        _ node: OpenJTalkFrontendNode,
        from phoneTone: [(phone: String, tone: Int)],
        index: inout [(phone: String, tone: Int)].Index
    ) {
        guard let punctuation = punctuationPhone(from: node.surface),
              index < phoneTone.endIndex,
              phoneTone[index].phone == punctuation else {
            return
        }
        index = phoneTone.index(after: index)
    }

    private static func accentType(fromMoraTones tones: [Int], fallback: Int) -> Int {
        guard !tones.isEmpty else {
            // No tone data available — trust OpenJTalk's accent value as-is (0 = heiban is valid).
            return fallback
        }
        guard let lastHighIndex = tones.lastIndex(where: { $0 > 0 }) else {
            // All moras low → heiban; preserve fallback which may be 0.
            return fallback
        }
        // Atamadaka (1型): first mora high AND second mora is low (or absent).
        let secondIsLow = tones.count < 2 || tones[1] == 0
        if tones[0] > 0, secondIsLow {
            return 1
        }
        // Nakadaka / odaka: pitch falls after lastHighIndex mora.
        return max(1, lastHighIndex + 1)
    }

    private static func pauseMora(for node: OpenJTalkFrontendNode) -> Mora? {
        guard node.partOfSpeech == "記号" else {
            return nil
        }
        switch node.surface {
        case "、", ",", "。", ".":
            return Mora(
                text: node.surface,
                consonant: nil,
                consonantLength: nil,
                vowel: "pau",
                vowelLength: 0.10,
                pitch: 0.0
            )
        default:
            return nil
        }
    }

    private static func partOfSpeech(for wordType: UserDictionaryEntry.WordType) -> String {
        switch wordType {
        case .properNoun:
            return "名詞"
        case .commonNoun:
            return "名詞"
        case .verb:
            return "動詞"
        case .adjective:
            return "形容詞"
        case .suffix:
            return "接尾辞"
        }
    }

    private static func katakana(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .applyingTransform(.hiraganaToKatakana, reverse: false)?
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func phoneToneWithoutPunctuation(from labels: [String]) -> [(phone: String, tone: Int)] {
        let prosodies = prosodySymbols(from: labels)
        var result: [(phone: String, tone: Int)] = []
        var currentPhrase: [(phone: String, tone: Int)] = []
        var currentTone = 0

        for (index, symbol) in prosodies.enumerated() {
            switch symbol {
            case "^":
                continue
            case "$", "?", "_", "#":
                result.append(contentsOf: fixedPhoneTone(currentPhrase))
                if symbol == "$" || symbol == "?" {
                    assert(index == prosodies.count - 1)
                }
                currentPhrase = []
                currentTone = 0
            case "[":
                currentTone += 1
            case "]":
                currentTone -= 1
            case "cl":
                currentPhrase.append(("q", currentTone))
            default:
                currentPhrase.append((symbol, currentTone))
            }
        }

        return result
    }

    private static func prosodySymbols(from labels: [String]) -> [String] {
        var phones: [String] = []
        for index in labels.indices {
            let label = labels[index]
            var p3 = numericString(in: label, pattern: #"\-(.*?)\+"#) ?? ""
            if ["A", "E", "I", "O", "U"].contains(p3) {
                p3 = p3.lowercased()
            }

            if p3 == "sil" {
                if index == labels.startIndex {
                    phones.append("^")
                } else if index == labels.index(before: labels.endIndex) {
                    let e3 = numericFeature(in: label, pattern: #"!(\d+)_"#)
                    phones.append(e3 == 1 ? "?" : "$")
                }
                continue
            }
            if p3 == "pau" {
                phones.append("_")
                continue
            }

            phones.append(p3)
            guard index < labels.index(before: labels.endIndex) else {
                continue
            }

            let a1 = numericFeature(in: label, pattern: #"/A:([0-9\-]+)\+"#)
            let a2 = numericFeature(in: label, pattern: #"\+(\d+)\+"#)
            let a3 = numericFeature(in: label, pattern: #"\+(\d+)/"#)
            let f1 = numericFeature(in: label, pattern: #"/F:(\d+)_"#)
            let a2Next = numericFeature(in: labels[labels.index(after: index)], pattern: #"\+(\d+)\+"#)

            if a3 == 1, a2Next == 1, isAccentPhraseBoundaryPhone(p3) {
                phones.append("#")
            } else if a1 == 0, a2Next == a2 + 1, a2 != f1 {
                phones.append("]")
            } else if a2 == 1, a2Next == 2 {
                phones.append("[")
            }
        }
        return phones
    }

    private static func fixedPhoneTone(_ phoneTone: [(phone: String, tone: Int)]) -> [(phone: String, tone: Int)] {
        let tones = Set(phoneTone.map(\.tone))
        if tones == Set([0]) || tones == Set([0, 1]) {
            return phoneTone
        }
        if tones == Set([-1, 0]) {
            return phoneTone.map { ($0.phone, $0.tone == -1 ? 0 : 1) }
        }
        return phoneTone.map { ($0.phone, $0.tone > 0 ? 1 : 0) }
    }

    private static func alignTones(
        phonesWithPunctuation: [String],
        phoneToneWithoutPunctuation: [(phone: String, tone: Int)]
    ) throws -> [(phone: String, tone: Int)] {
        var result: [(phone: String, tone: Int)] = []
        var toneIndex = phoneToneWithoutPunctuation.startIndex
        for phone in phonesWithPunctuation {
            if toneIndex >= phoneToneWithoutPunctuation.endIndex {
                result.append((phone, 0))
            } else if phone == phoneToneWithoutPunctuation[toneIndex].phone {
                result.append((phone, phoneToneWithoutPunctuation[toneIndex].tone))
                toneIndex += 1
            } else if isPunctuationPhone(phone) {
                result.append((phone, 0))
            } else {
                result.append((phone, 0))
            }
        }
        return result
    }

    private static func phonesWithPunctuation(from nodes: [OpenJTalkFrontendNode]) -> [String] {
        var result: [String] = []
        var previousVowel: String?
        for node in nodes {
            if let punctuation = punctuationPhone(from: node.surface) {
                result.append(punctuation)
                previousVowel = nil
                continue
            }
            for mora in JapaneseKanaFrontend.moras(from: node.pronunciation, styleID: 0) {
                let moraPhones = phones(for: mora, previousVowel: previousVowel)
                result.append(contentsOf: moraPhones)
                if let last = moraPhones.last, !isPunctuationPhone(last) {
                    previousVowel = last
                }
            }
        }
        return result
    }

    private static func wordToPhonemeCounts(from nodes: [OpenJTalkFrontendNode]) -> [Int] {
        nodes.flatMap { node in
            let textCount = max(1, normalizedSurface(node.surface).count)
            let phoneCount = max(1, phonesWithPunctuation(from: [node]).count)
            return distributePhone(phoneCount, across: textCount)
        }
    }

    private static func phones(for mora: Mora, previousVowel: String?) -> [String] {
        if mora.text == "ー" {
            return [longVowelPhone(from: previousVowel)]
        }
        if let punctuation = punctuationPhone(from: mora.text) {
            return [punctuation]
        }
        var phones: [String] = []
        if let consonant = mora.consonant {
            phones.append(consonant == "cl" ? "q" : consonant)
        }
        phones.append(normalizedVowel(mora.vowel))
        return phones
    }

    private static func normalizedVowel(_ vowel: String) -> String {
        switch vowel {
        case "pau":
            return ","
        case "cl":
            return "q"
        case "-":
            return "o:"
        default:
            return vowel
        }
    }

    private static func longVowelPhone(from previousVowel: String?) -> String {
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
            return "-"
        }
    }

    // Maps surface characters to the phoneme string they produce in OpenJTalk HTS labels.
    // Only「、」「。」(and their ASCII equivalents) actually generate a "pau" phoneme in the
    // label stream. All other punctuation (brackets, parens, hyphens, ！？…) produce NO
    // phoneme in the labels, so they must NOT be added to phonesWithPunctuation — doing so
    // inserts phantom entries into phoneTone that are never consumed and cause tone desync.
    private static func pausePhone(from text: String) -> String? {
        switch text {
        case "、", ",":
            return ","
        case "。", ".":
            return "."
        default:
            return nil
        }
    }

    // Legacy alias kept for isPunctuationPhone / phones(for:) call sites; returns nil for
    // non-pause punctuation so it is excluded from the phone alignment arrays.
    private static func punctuationPhone(from text: String) -> String? {
        pausePhone(from: text)
    }

    private static func normalizedSurface(_ raw: String) -> String {
        punctuationPhone(from: raw) ?? raw
    }

    private static func isPunctuationPhone(_ phone: String) -> Bool {
        [",", ".", "!", "?", "…", "'", "-"].contains(phone)
    }

    private static func isAccentPhraseBoundaryPhone(_ phone: String) -> Bool {
        ["a", "e", "i", "o", "u", "A", "E", "I", "O", "U", "N", "cl"].contains(phone)
    }

    // Pre-compiled regexes for HTS label feature extraction.
    // Compiling these on every call was the dominant per-synthesis CPU cost (~500 compilations).
    private static let compiledRegexes: [String: NSRegularExpression] = {
        let patterns = [
            #"\-(.*?)\+"#,
            #"!(\d+)_"#,
            #"/A:([0-9\-]+)\+"#,
            #"\+(\d+)\+"#,
            #"\+(\d+)/"#,
            #"/F:(\d+)_"#,
        ]
        return Dictionary(uniqueKeysWithValues: patterns.compactMap { pattern in
            (try? NSRegularExpression(pattern: pattern)).map { (pattern, $0) }
        })
    }()

    private static func numericFeature(in text: String, pattern: String) -> Int {
        guard let value = numericString(in: text, pattern: pattern) else {
            return -50
        }
        return Int(value) ?? -50
    }

    private static func numericString(in text: String, pattern: String) -> String? {
        let regex = compiledRegexes[pattern] ?? (try? NSRegularExpression(pattern: pattern))
        guard let regex,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
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
}
