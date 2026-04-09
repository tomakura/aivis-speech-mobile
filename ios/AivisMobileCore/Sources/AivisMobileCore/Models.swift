import Foundation

public struct VoiceReference: Codable, Equatable, Sendable {
    public var engineID: String
    public var speakerID: String
    public var styleID: Int

    public init(engineID: String, speakerID: String, styleID: Int) {
        self.engineID = engineID
        self.speakerID = speakerID
        self.styleID = styleID
    }

    enum CodingKeys: String, CodingKey {
        case engineID = "engineId"
        case speakerID = "speakerId"
        case styleID = "styleId"
    }
}

public enum OutputSamplingRate: Codable, Equatable, Sendable {
    case engineDefault
    case explicit(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(String.self), raw == "engineDefault" {
            self = .engineDefault
            return
        }
        self = .explicit(try container.decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .engineDefault:
            try container.encode("engineDefault")
        case let .explicit(value):
            try container.encode(value)
        }
    }
}

public struct Mora: Codable, Equatable, Sendable {
    public var text: String
    public var consonant: String?
    public var consonantLength: Double?
    public var vowel: String
    public var vowelLength: Double
    public var pitch: Double

    public init(
        text: String,
        consonant: String? = nil,
        consonantLength: Double? = nil,
        vowel: String,
        vowelLength: Double,
        pitch: Double
    ) {
        self.text = text
        self.consonant = consonant
        self.consonantLength = consonantLength
        self.vowel = vowel
        self.vowelLength = vowelLength
        self.pitch = pitch
    }
}

public struct AccentPhrase: Codable, Equatable, Sendable {
    public var moras: [Mora]
    public var accent: Int
    public var pauseMora: Mora?
    public var isInterrogative: Bool?

    public init(
        moras: [Mora],
        accent: Int,
        pauseMora: Mora? = nil,
        isInterrogative: Bool? = nil
    ) {
        self.moras = moras
        self.accent = accent
        self.pauseMora = pauseMora
        self.isInterrogative = isInterrogative
    }
}

public struct AudioQuery: Codable, Equatable, Sendable {
    public var accentPhrases: [AccentPhrase]
    public var speedScale: Double
    public var intonationScale: Double
    public var tempoDynamicsScale: Double?
    public var pitchScale: Double
    public var volumeScale: Double
    public var pauseLengthScale: Double
    public var prePhonemeLength: Double
    public var postPhonemeLength: Double
    public var outputSamplingRate: OutputSamplingRate
    public var outputStereo: Bool
    public var kana: String?

    public init(
        accentPhrases: [AccentPhrase],
        speedScale: Double,
        intonationScale: Double,
        tempoDynamicsScale: Double? = nil,
        pitchScale: Double,
        volumeScale: Double,
        pauseLengthScale: Double,
        prePhonemeLength: Double,
        postPhonemeLength: Double,
        outputSamplingRate: OutputSamplingRate,
        outputStereo: Bool,
        kana: String? = nil
    ) {
        self.accentPhrases = accentPhrases
        self.speedScale = speedScale
        self.intonationScale = intonationScale
        self.tempoDynamicsScale = tempoDynamicsScale
        self.pitchScale = pitchScale
        self.volumeScale = volumeScale
        self.pauseLengthScale = pauseLengthScale
        self.prePhonemeLength = prePhonemeLength
        self.postPhonemeLength = postPhonemeLength
        self.outputSamplingRate = outputSamplingRate
        self.outputStereo = outputStereo
        self.kana = kana
    }

    enum CodingKeys: String, CodingKey {
        case accentPhrases
        case speedScale
        case intonationScale
        case tempoDynamicsScale
        case pitchScale
        case volumeScale
        case pauseLengthScale
        case prePhonemeLength
        case postPhonemeLength
        case outputSamplingRate
        case outputStereo
        case kana
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accentPhrases = try container.decode([AccentPhrase].self, forKey: .accentPhrases)
        self.speedScale = try container.decode(Double.self, forKey: .speedScale)
        self.intonationScale = try container.decode(Double.self, forKey: .intonationScale)
        self.tempoDynamicsScale = try container.decodeIfPresent(Double.self, forKey: .tempoDynamicsScale)
        self.pitchScale = try container.decode(Double.self, forKey: .pitchScale)
        self.volumeScale = try container.decode(Double.self, forKey: .volumeScale)
        self.pauseLengthScale = try container.decodeIfPresent(Double.self, forKey: .pauseLengthScale) ?? 1.0
        self.prePhonemeLength = try container.decode(Double.self, forKey: .prePhonemeLength)
        self.postPhonemeLength = try container.decode(Double.self, forKey: .postPhonemeLength)
        self.outputSamplingRate = try container.decode(OutputSamplingRate.self, forKey: .outputSamplingRate)
        self.outputStereo = try container.decode(Bool.self, forKey: .outputStereo)
        self.kana = try container.decodeIfPresent(String.self, forKey: .kana)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accentPhrases, forKey: .accentPhrases)
        try container.encode(speedScale, forKey: .speedScale)
        try container.encode(intonationScale, forKey: .intonationScale)
        try container.encodeIfPresent(tempoDynamicsScale, forKey: .tempoDynamicsScale)
        try container.encode(pitchScale, forKey: .pitchScale)
        try container.encode(volumeScale, forKey: .volumeScale)
        try container.encode(pauseLengthScale, forKey: .pauseLengthScale)
        try container.encode(prePhonemeLength, forKey: .prePhonemeLength)
        try container.encode(postPhonemeLength, forKey: .postPhonemeLength)
        try container.encode(outputSamplingRate, forKey: .outputSamplingRate)
        try container.encode(outputStereo, forKey: .outputStereo)
        try container.encodeIfPresent(kana, forKey: .kana)
    }
}

public struct MorphingInfo: Codable, Equatable, Sendable {
    public var rate: Double
    public var targetEngineID: String
    public var targetSpeakerID: String
    public var targetStyleID: Int

    public init(rate: Double, targetEngineID: String, targetSpeakerID: String, targetStyleID: Int) {
        self.rate = rate
        self.targetEngineID = targetEngineID
        self.targetSpeakerID = targetSpeakerID
        self.targetStyleID = targetStyleID
    }

    enum CodingKeys: String, CodingKey {
        case rate
        case targetEngineID = "targetEngineId"
        case targetSpeakerID = "targetSpeakerId"
        case targetStyleID = "targetStyleId"
    }
}

public struct AudioItem: Codable, Equatable, Sendable {
    public var text: String
    public var voice: VoiceReference
    public var query: AudioQuery?
    public var presetKey: String?
    public var morphingInfo: MorphingInfo?

    public init(
        text: String,
        voice: VoiceReference,
        query: AudioQuery? = nil,
        presetKey: String? = nil,
        morphingInfo: MorphingInfo? = nil
    ) {
        self.text = text
        self.voice = voice
        self.query = query
        self.presetKey = presetKey
        self.morphingInfo = morphingInfo
    }
}

public struct Tempo: Codable, Equatable, Sendable {
    public var position: Int
    public var bpm: Double

    public init(position: Int, bpm: Double) {
        self.position = position
        self.bpm = bpm
    }
}

public struct TimeSignature: Codable, Equatable, Sendable {
    public var measureNumber: Int
    public var beats: Int
    public var beatType: Int

    public init(measureNumber: Int, beats: Int, beatType: Int) {
        self.measureNumber = measureNumber
        self.beats = beats
        self.beatType = beatType
    }
}

public struct Singer: Codable, Equatable, Sendable {
    public var engineID: String
    public var styleID: Int

    public init(engineID: String, styleID: Int) {
        self.engineID = engineID
        self.styleID = styleID
    }

    enum CodingKeys: String, CodingKey {
        case engineID = "engineId"
        case styleID = "styleId"
    }
}

public struct Note: Codable, Equatable, Sendable {
    public var id: String
    public var position: Double
    public var duration: Double
    public var noteNumber: Int
    public var lyric: String

    public init(id: String, position: Double, duration: Double, noteNumber: Int, lyric: String) {
        self.id = id
        self.position = position
        self.duration = duration
        self.noteNumber = noteNumber
        self.lyric = lyric
    }
}

public struct Track: Codable, Equatable, Sendable {
    public var name: String
    public var singer: Singer?
    public var keyRangeAdjustment: Double
    public var volumeRangeAdjustment: Double
    public var notes: [Note]
    public var pitchEditData: [Double]
    public var solo: Bool
    public var mute: Bool
    public var gain: Double
    public var pan: Double

    public init(
        name: String,
        singer: Singer? = nil,
        keyRangeAdjustment: Double,
        volumeRangeAdjustment: Double,
        notes: [Note],
        pitchEditData: [Double],
        solo: Bool,
        mute: Bool,
        gain: Double,
        pan: Double
    ) {
        self.name = name
        self.singer = singer
        self.keyRangeAdjustment = keyRangeAdjustment
        self.volumeRangeAdjustment = volumeRangeAdjustment
        self.notes = notes
        self.pitchEditData = pitchEditData
        self.solo = solo
        self.mute = mute
        self.gain = gain
        self.pan = pan
    }
}

public struct TalkProject: Codable, Equatable, Sendable {
    public var audioKeys: [String]
    public var audioItems: [String: AudioItem]

    public init(audioKeys: [String], audioItems: [String: AudioItem]) {
        self.audioKeys = audioKeys
        self.audioItems = audioItems
    }
}

public struct SongProject: Codable, Equatable, Sendable {
    public var tpqn: Int
    public var tempos: [Tempo]
    public var timeSignatures: [TimeSignature]
    public var tracks: [String: Track]
    public var trackOrder: [String]

    public init(
        tpqn: Int,
        tempos: [Tempo],
        timeSignatures: [TimeSignature],
        tracks: [String: Track],
        trackOrder: [String]
    ) {
        self.tpqn = tpqn
        self.tempos = tempos
        self.timeSignatures = timeSignatures
        self.tracks = tracks
        self.trackOrder = trackOrder
    }

    public static let empty = SongProject(
        tpqn: 480,
        tempos: [Tempo(position: 0, bpm: 120.0)],
        timeSignatures: [TimeSignature(measureNumber: 1, beats: 4, beatType: 4)],
        tracks: [:],
        trackOrder: []
    )
}

public struct AISPProjectDocument: Codable, Equatable, Sendable {
    public var appVersion: String
    public var talk: TalkProject
    public var song: SongProject

    public init(appVersion: String, talk: TalkProject, song: SongProject) {
        self.appVersion = appVersion
        self.talk = talk
        self.song = song
    }
}

public struct Preset: Codable, Equatable, Sendable {
    public var name: String
    public var speedScale: Double
    public var intonationScale: Double
    public var tempoDynamicsScale: Double?
    public var pitchScale: Double
    public var volumeScale: Double
    public var pauseLengthScale: Double
    public var prePhonemeLength: Double
    public var postPhonemeLength: Double

    public init(
        name: String,
        speedScale: Double,
        intonationScale: Double,
        tempoDynamicsScale: Double? = nil,
        pitchScale: Double,
        volumeScale: Double,
        pauseLengthScale: Double,
        prePhonemeLength: Double,
        postPhonemeLength: Double
    ) {
        self.name = name
        self.speedScale = speedScale
        self.intonationScale = intonationScale
        self.tempoDynamicsScale = tempoDynamicsScale
        self.pitchScale = pitchScale
        self.volumeScale = volumeScale
        self.pauseLengthScale = pauseLengthScale
        self.prePhonemeLength = prePhonemeLength
        self.postPhonemeLength = postPhonemeLength
    }
}

public struct PresetCatalog: Codable, Equatable, Sendable {
    public var items: [String: Preset]
    public var keys: [String]

    public init(items: [String: Preset], keys: [String]) {
        self.items = items
        self.keys = keys
    }
}

public struct DefaultStyleID: Codable, Equatable, Sendable {
    public var engineID: String
    public var speakerUUID: String
    public var defaultStyleID: Int

    public init(engineID: String, speakerUUID: String, defaultStyleID: Int) {
        self.engineID = engineID
        self.speakerUUID = speakerUUID
        self.defaultStyleID = defaultStyleID
    }

    enum CodingKeys: String, CodingKey {
        case engineID = "engineId"
        case speakerUUID = "speakerUuid"
        case defaultStyleID = "defaultStyleId"
    }
}

public struct UserDictionaryEntry: Codable, Equatable, Sendable, Identifiable {
    public enum WordType: String, Codable, Sendable {
        case properNoun = "PROPER_NOUN"
        case commonNoun = "COMMON_NOUN"
        case verb = "VERB"
        case adjective = "ADJECTIVE"
        case suffix = "SUFFIX"
    }

    public var id: UUID
    public var surface: String
    public var pronunciation: String
    public var accentType: Int
    public var wordType: WordType
    public var priority: Int

    public init(
        id: UUID,
        surface: String,
        pronunciation: String,
        accentType: Int,
        wordType: WordType,
        priority: Int
    ) {
        self.id = id
        self.surface = surface
        self.pronunciation = pronunciation
        self.accentType = accentType
        self.wordType = wordType
        self.priority = priority
    }
}

public struct UserDictionary: Codable, Equatable, Sendable {
    public var entries: [UserDictionaryEntry]

    public init(entries: [UserDictionaryEntry]) {
        self.entries = entries
    }
}

public enum DiagnosticWAVWriterError: LocalizedError {
    case invalidSampleRate(Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidSampleRate(sampleRate):
            return "Invalid sample rate: \(sampleRate)."
        }
    }
}

public enum DiagnosticWAVWriter {
    public static func makeWAVData(
        from query: AudioQuery,
        text: String? = nil,
        sampleRate: Int = 44_100
    ) throws -> Data {
        guard sampleRate > 0 else {
            throw DiagnosticWAVWriterError.invalidSampleRate(sampleRate)
        }

        let channelCount = query.outputStereo ? 2 : 1
        let duration = renderDuration(for: query, text: text)
        let frameCount = max(1, Int(Double(sampleRate) * duration))
        let sampleSeed = stableSeed(for: query, text: text)
        let frequency = 180.0 + Double(sampleSeed % 360)
        let amplitude = max(0.05, min(0.9, 0.18 + query.volumeScale * 0.22))
        let detune = 0.02 + min(0.04, abs(query.pitchScale) * 0.01)

        var pcm = Data()
        pcm.reserveCapacity(frameCount * channelCount * MemoryLayout<Int16>.size)

        for frameIndex in 0..<frameCount {
            let time = Double(frameIndex) / Double(sampleRate)
            let envelope = amplitudeEnvelope(for: time, duration: duration)
            let speedFactor = max(0.55, min(1.65, query.speedScale))
            let pitchFactor = 1.0 + query.pitchScale * 0.15
            let tonalFrequency = frequency * pitchFactor * speedFactor
            let base = sin(2.0 * .pi * tonalFrequency * time)
            let shimmer = 0.35 * sin(2.0 * .pi * tonalFrequency * 2.0 * time)
            let leftSample = clampedSample((base + shimmer * 0.25) * envelope * amplitude)

            if channelCount == 2 {
                let rightFrequency = tonalFrequency * (1.0 + detune)
                let rightBase = sin(2.0 * .pi * rightFrequency * time)
                let rightShimmer = 0.35 * sin(2.0 * .pi * rightFrequency * 2.0 * time)
                let rightSample = clampedSample((rightBase + rightShimmer * 0.25) * envelope * amplitude)
                pcm.append(contentsOf: leftSample.leBytes)
                pcm.append(contentsOf: rightSample.leBytes)
            } else {
                pcm.append(contentsOf: leftSample.leBytes)
            }
        }

        let byteRate = sampleRate * channelCount * MemoryLayout<Int16>.size
        let blockAlign = channelCount * MemoryLayout<Int16>.size
        let dataChunkSize = pcm.count
        let riffChunkSize = 36 + dataChunkSize

        var wav = Data()
        wav.reserveCapacity(44 + dataChunkSize)
        wav.appendAscii("RIFF")
        wav.appendLittleEndian(UInt32(riffChunkSize))
        wav.appendAscii("WAVE")
        wav.appendAscii("fmt ")
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt16(channelCount))
        wav.appendLittleEndian(UInt32(sampleRate))
        wav.appendLittleEndian(UInt32(byteRate))
        wav.appendLittleEndian(UInt16(blockAlign))
        wav.appendLittleEndian(UInt16(16))
        wav.appendAscii("data")
        wav.appendLittleEndian(UInt32(dataChunkSize))
        wav.append(pcm)
        return wav
    }

    private static func renderDuration(for query: AudioQuery, text: String?) -> TimeInterval {
        let sourceLength = max(text?.count ?? 0, query.kana?.count ?? 0)
        let base = max(0.8, Double(sourceLength) * 0.065)
        let speedAdjusted = base / max(0.75, min(1.5, query.speedScale))
        return min(4.0, max(0.8, speedAdjusted))
    }

    private static func stableSeed(for query: AudioQuery, text: String?) -> UInt64 {
        let components = [
            text ?? "",
            query.kana ?? "",
            String(query.speedScale),
            String(query.intonationScale),
            String(query.pitchScale),
            String(query.volumeScale),
            String(query.pauseLengthScale),
        ]
        var hash: UInt64 = 1469598103934665603
        for byte in components.joined(separator: "|").utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    private static func amplitudeEnvelope(for time: TimeInterval, duration: TimeInterval) -> Double {
        let fadeDuration = min(0.06, duration * 0.15)
        let attack = min(1.0, time / max(0.0001, fadeDuration))
        let release = min(1.0, (duration - time) / max(0.0001, fadeDuration))
        return max(0.0, min(1.0, attack * release))
    }

    private static func clampedSample(_ value: Double) -> Int16 {
        let scaled = max(-1.0, min(1.0, value)) * Double(Int16.max) * 0.82
        return Int16(scaled.rounded())
    }
}

public struct WAVPCMFormat: Equatable, Sendable, CustomStringConvertible {
    public var audioFormat: UInt16
    public var channelCount: UInt16
    public var sampleRate: UInt32
    public var byteRate: UInt32
    public var blockAlign: UInt16
    public var bitsPerSample: UInt16

    public var description: String {
        "format=\(audioFormat), channels=\(channelCount), sampleRate=\(sampleRate), bits=\(bitsPerSample)"
    }
}

public enum WAVConcatenationError: LocalizedError, Equatable {
    case emptyInput
    case invalidRIFF
    case missingChunk(String)
    case unsupportedFormat(String)
    case formatMismatch(expected: String, actual: String)
    case oversizedData(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "No WAV data was provided."
        case .invalidRIFF:
            return "The WAV data is not a valid RIFF/WAVE file."
        case let .missingChunk(name):
            return "The WAV data is missing the \(name) chunk."
        case let .unsupportedFormat(format):
            return "Only 16-bit PCM WAV data can be concatenated. Received \(format)."
        case let .formatMismatch(expected, actual):
            return "WAV formats must match before concatenation. Expected \(expected), received \(actual)."
        case let .oversizedData(size):
            return "The concatenated WAV data is too large: \(size) bytes."
        }
    }
}

public enum WAVDataConcatenator {
    public static func concatenate(_ wavs: [Data]) throws -> Data {
        guard !wavs.isEmpty else {
            throw WAVConcatenationError.emptyInput
        }

        let segments = try wavs.map(parseSegment)
        let format = segments[0].format

        for segment in segments {
            guard segment.format == format else {
                throw WAVConcatenationError.formatMismatch(
                    expected: format.description,
                    actual: segment.format.description
                )
            }
        }

        let dataChunkSize = segments.reduce(0) { $0 + $1.pcmData.count }
        guard dataChunkSize <= Int(UInt32.max) - 36 else {
            throw WAVConcatenationError.oversizedData(dataChunkSize)
        }

        var wav = Data()
        wav.reserveCapacity(44 + dataChunkSize)
        wav.appendAscii("RIFF")
        wav.appendLittleEndian(UInt32(36 + dataChunkSize))
        wav.appendAscii("WAVE")
        wav.appendAscii("fmt ")
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(format.audioFormat)
        wav.appendLittleEndian(format.channelCount)
        wav.appendLittleEndian(format.sampleRate)
        wav.appendLittleEndian(format.byteRate)
        wav.appendLittleEndian(format.blockAlign)
        wav.appendLittleEndian(format.bitsPerSample)
        wav.appendAscii("data")
        wav.appendLittleEndian(UInt32(dataChunkSize))
        for segment in segments {
            wav.append(segment.pcmData)
        }
        return wav
    }

    private struct Segment {
        var format: WAVPCMFormat
        var pcmData: Data
    }

    private static func parseSegment(_ wav: Data) throws -> Segment {
        guard wav.count >= 12,
              wav.asciiString(in: 0..<4) == "RIFF",
              wav.asciiString(in: 8..<12) == "WAVE" else {
            throw WAVConcatenationError.invalidRIFF
        }

        var cursor = 12
        var format: WAVPCMFormat?
        var pcmData: Data?

        while cursor + 8 <= wav.count {
            let idRange = cursor..<(cursor + 4)
            let chunkID = wav.asciiString(in: idRange)
            let chunkSize = try wav.readLittleEndianUInt32(at: cursor + 4)
            let dataStart = cursor + 8
            let dataEnd = dataStart + Int(chunkSize)
            guard dataEnd <= wav.count else {
                throw WAVConcatenationError.invalidRIFF
            }

            switch chunkID {
            case "fmt ":
                guard chunkSize >= 16 else {
                    throw WAVConcatenationError.missingChunk("fmt")
                }
                format = try WAVPCMFormat(
                    audioFormat: wav.readLittleEndianUInt16(at: dataStart),
                    channelCount: wav.readLittleEndianUInt16(at: dataStart + 2),
                    sampleRate: wav.readLittleEndianUInt32(at: dataStart + 4),
                    byteRate: wav.readLittleEndianUInt32(at: dataStart + 8),
                    blockAlign: wav.readLittleEndianUInt16(at: dataStart + 12),
                    bitsPerSample: wav.readLittleEndianUInt16(at: dataStart + 14)
                )
            case "data":
                pcmData = Data(wav[dataStart..<dataEnd])
            default:
                break
            }

            cursor = dataEnd + (Int(chunkSize) % 2)
        }

        guard let format else {
            throw WAVConcatenationError.missingChunk("fmt")
        }
        guard let pcmData else {
            throw WAVConcatenationError.missingChunk("data")
        }
        guard format.audioFormat == 1, format.bitsPerSample == 16 else {
            throw WAVConcatenationError.unsupportedFormat(format.description)
        }
        return Segment(format: format, pcmData: pcmData)
    }
}

private extension Data {
    mutating func appendAscii(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    func asciiString(in range: Range<Int>) -> String? {
        guard range.lowerBound >= startIndex, range.upperBound <= endIndex else {
            return nil
        }
        return String(data: self[range], encoding: .ascii)
    }

    func readLittleEndianUInt16(at offset: Int) throws -> UInt16 {
        guard offset >= startIndex, offset + 2 <= endIndex else {
            throw WAVConcatenationError.invalidRIFF
        }
        let first = UInt16(self[offset])
        let second = UInt16(self[offset + 1]) << 8
        return first | second
    }

    func readLittleEndianUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= startIndex, offset + 4 <= endIndex else {
            throw WAVConcatenationError.invalidRIFF
        }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}

private extension Int16 {
    var leBytes: [UInt8] {
        let value = littleEndian
        return [
            UInt8(truncatingIfNeeded: value & 0x00FF),
            UInt8(truncatingIfNeeded: (value >> 8) & 0x00FF)
        ]
    }
}
