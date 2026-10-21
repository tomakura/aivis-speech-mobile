import Foundation
import AivisMobileCore

public enum RemoteAivisSpeechEngineError: LocalizedError, Equatable {
    case invalidBaseURL(String)
    case invalidEndpoint(String)
    case requestFailed(endpoint: String, statusCode: Int, body: String)
    case styleMappingFailed(localStyleID: Int, modelName: String?)

    public var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(value):
            return "AivisSpeech Engine URL が正しくありません: \(value)"
        case let .invalidEndpoint(endpoint):
            return "AivisSpeech Engine のエンドポイント URL を作成できません: \(endpoint)"
        case let .requestFailed(endpoint, statusCode, body):
            let detail = body.isEmpty ? "レスポンス本文なし" : body
            return "AivisSpeech Engine \(endpoint) が失敗しました。HTTP \(statusCode): \(detail)"
        case let .styleMappingFailed(localStyleID, modelName):
            let modelLabel = modelName ?? "アクティブモデル未確定"
            return "AivisSpeech Engine 側のスタイルIDへ変換できませんでした。model=\(modelLabel), localStyleID=\(localStyleID)"
        }
    }
}

public struct RemoteAivisSpeechEngine: SpeechEngine {
    public static let userDefaultsKey = "AivisRemoteEngineURLOverride"
    public static let enabledUserDefaultsKey = "AivisRemoteEngineURLEnabled"

    private let baseURL: URL
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        baseURL: URL,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.decoder = decoder
        self.encoder = encoder
    }

    public init(baseURLString: String) throws {
        guard let url = URL(string: baseURLString), url.scheme != nil, url.host != nil else {
            throw RemoteAivisSpeechEngineError.invalidBaseURL(baseURLString)
        }
        self.init(baseURL: url)
    }

    public static var configuredBaseURL: URL? {
        guard UserDefaults.standard.bool(forKey: enabledUserDefaultsKey) else {
            return nil
        }
        let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawValue, !rawValue.isEmpty {
            return URL(string: rawValue)
        }

        return nil
    }

    public func supportedDevices() async throws -> SupportedDevices {
        SupportedDevices(cpu: true, gpu: true, neuralEnginePreferred: false, coreML: false)
    }

    public func makeAudioQuery(text: String, styleID: Int) async throws -> AudioQuery {
        let data = try await post(endpoint: "audio_query", speaker: styleID, text: text, body: nil)
        return try decoder.decode(RemoteAudioQueryPayload.self, from: data).audioQuery
    }

    public func synthesize(query: AudioQuery, styleID: Int) async throws -> Data {
        let payload = RemoteAudioQueryPayload(audioQuery: query)
        let body = try encoder.encode(payload)
        return try await post(endpoint: "synthesis", speaker: styleID, text: nil, body: body)
    }

    public func resolveStyleID(localStyleID: Int, activeModel: InstalledModel?) async throws -> Int {
        let speakers = try await speakers()
        if speakers.flatMap(\.styles).contains(where: { $0.id == localStyleID }) {
            return localStyleID
        }

        guard let activeModel,
              let remoteSpeaker = remoteSpeaker(for: activeModel, in: speakers) else {
            throw RemoteAivisSpeechEngineError.styleMappingFailed(
                localStyleID: localStyleID,
                modelName: activeModel?.name
            )
        }

        if let localStyleName = localStyleName(for: localStyleID, in: activeModel),
           let remoteStyle = remoteSpeaker.styles.first(where: { $0.name == localStyleName }) {
            return remoteStyle.id
        }

        let sortedLocalStyles = localStyles(in: activeModel).sorted { $0.localID < $1.localID }
        if let localIndex = sortedLocalStyles.firstIndex(where: { $0.localID == localStyleID }),
           remoteSpeaker.styles.indices.contains(localIndex) {
            return remoteSpeaker.styles[localIndex].id
        }

        if remoteSpeaker.styles.indices.contains(localStyleID), localStyleID >= 0 {
            return remoteSpeaker.styles[localStyleID].id
        }

        throw RemoteAivisSpeechEngineError.styleMappingFailed(
            localStyleID: localStyleID,
            modelName: activeModel.name
        )
    }

    private func speakers() async throws -> [RemoteSpeakerPayload] {
        let data = try await get(endpoint: "speakers")
        return try decoder.decode([RemoteSpeakerPayload].self, from: data)
    }

    private func get(endpoint: String) async throws -> Data {
        guard let url = URLComponents(
            url: baseURL.appendingPathComponent(endpoint),
            resolvingAgainstBaseURL: false
        )?.url else {
            throw RemoteAivisSpeechEngineError.invalidEndpoint(endpoint)
        }

        let (data, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw RemoteAivisSpeechEngineError.requestFailed(
                endpoint: endpoint,
                statusCode: statusCode,
                body: responseBody
            )
        }
        return data
    }

    private func post(endpoint: String, speaker: Int, text: String?, body: Data?) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "speaker", value: String(speaker))]
        if let text {
            queryItems.append(URLQueryItem(name: "text", value: text))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw RemoteAivisSpeechEngineError.invalidEndpoint(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw RemoteAivisSpeechEngineError.requestFailed(
                endpoint: endpoint,
                statusCode: statusCode,
                body: responseBody
            )
        }
        return data
    }
}

public struct UserDefaultsConfiguredSpeechEngine: SpeechEngine {
    private let nativeEngine: any SpeechEngine
    private let modelRepository: (any ModelRepository)?

    public init(nativeEngine: any SpeechEngine, modelRepository: (any ModelRepository)? = nil) {
        self.nativeEngine = nativeEngine
        self.modelRepository = modelRepository
    }

    public func supportedDevices() async throws -> SupportedDevices {
        if let remoteEngine = remoteEngine() {
            return try await remoteEngine.supportedDevices()
        }
        return try await nativeEngine.supportedDevices()
    }

    public func makeAudioQuery(text: String, styleID: Int) async throws -> AudioQuery {
        if let remoteEngine = remoteEngine() {
            let remoteStyleID = try await remoteStyleID(for: styleID, remoteEngine: remoteEngine)
            let query = try await remoteEngine.makeAudioQuery(text: text, styleID: remoteStyleID)
            return DictionaryAwareAudioQuery.applySharedUserDictionary(
                to: query,
                text: text,
                styleID: styleID
            )
        }
        let query = try await nativeEngine.makeAudioQuery(text: text, styleID: styleID)
        return DictionaryAwareAudioQuery.applySharedUserDictionary(
            to: query,
            text: text,
            styleID: styleID
        )
    }

    public func synthesize(query: AudioQuery, styleID: Int) async throws -> Data {
        if let remoteEngine = remoteEngine() {
            let remoteStyleID = try await remoteStyleID(for: styleID, remoteEngine: remoteEngine)
            return try await remoteEngine.synthesize(query: query, styleID: remoteStyleID)
        }
        return try await nativeEngine.synthesize(query: query, styleID: styleID)
    }

    private func remoteStyleID(for localStyleID: Int, remoteEngine: RemoteAivisSpeechEngine) async throws -> Int {
        let activeModel = try await modelRepository?.installedModels().first(where: { $0.loadState == .active })
        return try await remoteEngine.resolveStyleID(localStyleID: localStyleID, activeModel: activeModel)
    }

    private func remoteEngine() -> RemoteAivisSpeechEngine? {
        guard let baseURL = RemoteAivisSpeechEngine.configuredBaseURL else {
            return nil
        }
        return RemoteAivisSpeechEngine(baseURL: baseURL)
    }
}

private func remoteSpeaker(for activeModel: InstalledModel, in speakers: [RemoteSpeakerPayload]) -> RemoteSpeakerPayload? {
    let activeName = normalizedModelName(activeModel.name)
    return speakers.first { normalizedModelName($0.name) == activeName }
        ?? speakers.first {
            let candidateName = normalizedModelName($0.name)
            return activeName.contains(candidateName) || candidateName.contains(activeName)
        }
}

private func localStyles(in activeModel: InstalledModel) -> [ModelStyleRuntimeMetadata] {
    if let styleProfiles = activeModel.manifest?.runtimeDescriptor?.styleProfiles, !styleProfiles.isEmpty {
        return styleProfiles
    }
    return activeModel.manifest?.speakers.flatMap(\.styles).map {
        ModelStyleRuntimeMetadata(localID: $0.localID, name: $0.name)
    } ?? []
}

private func localStyleName(for localStyleID: Int, in activeModel: InstalledModel) -> String? {
    localStyles(in: activeModel).first(where: { $0.localID == localStyleID })?.name
}

private func normalizedModelName(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

struct RemoteSpeakerPayload: Codable, Equatable {
    var name: String
    var speakerUUID: String
    var styles: [RemoteSpeakerStylePayload]

    enum CodingKeys: String, CodingKey {
        case name
        case speakerUUID = "speaker_uuid"
        case styles
    }
}

struct RemoteSpeakerStylePayload: Codable, Equatable {
    var name: String
    var id: Int
    var type: String?
}

struct RemoteAudioQueryPayload: Codable, Equatable {
    var accentPhrases: [RemoteAccentPhrasePayload]
    var speedScale: Double
    var intonationScale: Double
    var tempoDynamicsScale: Double
    var pitchScale: Double
    var volumeScale: Double
    var prePhonemeLength: Double
    var postPhonemeLength: Double
    var pauseLength: Double?
    var pauseLengthScale: Double
    var outputSamplingRate: Int
    var outputStereo: Bool
    var kana: String?

    init(audioQuery: AudioQuery) {
        self.accentPhrases = audioQuery.accentPhrases.map(RemoteAccentPhrasePayload.init(accentPhrase:))
        self.speedScale = audioQuery.speedScale
        self.intonationScale = audioQuery.intonationScale
        self.tempoDynamicsScale = audioQuery.tempoDynamicsScale ?? 1.0
        self.pitchScale = audioQuery.pitchScale
        self.volumeScale = audioQuery.volumeScale
        self.prePhonemeLength = audioQuery.prePhonemeLength
        self.postPhonemeLength = audioQuery.postPhonemeLength
        self.pauseLength = nil
        self.pauseLengthScale = audioQuery.pauseLengthScale
        switch audioQuery.outputSamplingRate {
        case .engineDefault:
            self.outputSamplingRate = 44_100
        case let .explicit(value):
            self.outputSamplingRate = value
        }
        self.outputStereo = audioQuery.outputStereo
        self.kana = audioQuery.kana
    }

    var audioQuery: AudioQuery {
        AudioQuery(
            accentPhrases: accentPhrases.map(\.accentPhrase),
            speedScale: speedScale,
            intonationScale: intonationScale,
            tempoDynamicsScale: tempoDynamicsScale,
            pitchScale: pitchScale,
            volumeScale: volumeScale,
            pauseLengthScale: pauseLengthScale,
            prePhonemeLength: prePhonemeLength,
            postPhonemeLength: postPhonemeLength,
            outputSamplingRate: .explicit(outputSamplingRate),
            outputStereo: outputStereo,
            kana: kana
        )
    }

    enum CodingKeys: String, CodingKey {
        case accentPhrases = "accent_phrases"
        case speedScale
        case intonationScale
        case tempoDynamicsScale
        case pitchScale
        case volumeScale
        case prePhonemeLength
        case postPhonemeLength
        case pauseLength
        case pauseLengthScale
        case outputSamplingRate
        case outputStereo
        case kana
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accentPhrases, forKey: .accentPhrases)
        try container.encode(speedScale, forKey: .speedScale)
        try container.encode(intonationScale, forKey: .intonationScale)
        try container.encode(tempoDynamicsScale, forKey: .tempoDynamicsScale)
        try container.encode(pitchScale, forKey: .pitchScale)
        try container.encode(volumeScale, forKey: .volumeScale)
        try container.encode(prePhonemeLength, forKey: .prePhonemeLength)
        try container.encode(postPhonemeLength, forKey: .postPhonemeLength)
        try container.encodeNil(forKey: .pauseLength)
        try container.encode(pauseLengthScale, forKey: .pauseLengthScale)
        try container.encode(outputSamplingRate, forKey: .outputSamplingRate)
        try container.encode(outputStereo, forKey: .outputStereo)
        try container.encodeIfPresent(kana, forKey: .kana)
    }
}

struct RemoteAccentPhrasePayload: Codable, Equatable {
    var moras: [RemoteMoraPayload]
    var accent: Int
    var pauseMora: RemoteMoraPayload?
    var isInterrogative: Bool

    init(accentPhrase: AccentPhrase) {
        self.moras = accentPhrase.moras.map(RemoteMoraPayload.init(mora:))
        self.accent = accentPhrase.accent
        self.pauseMora = accentPhrase.pauseMora.map(RemoteMoraPayload.init(mora:))
        self.isInterrogative = accentPhrase.isInterrogative ?? false
    }

    var accentPhrase: AccentPhrase {
        AccentPhrase(
            moras: moras.map(\.mora),
            accent: accent,
            pauseMora: pauseMora?.mora,
            isInterrogative: isInterrogative
        )
    }

    enum CodingKeys: String, CodingKey {
        case moras
        case accent
        case pauseMora = "pause_mora"
        case isInterrogative = "is_interrogative"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(moras, forKey: .moras)
        try container.encode(accent, forKey: .accent)
        if let pauseMora {
            try container.encode(pauseMora, forKey: .pauseMora)
        } else {
            try container.encodeNil(forKey: .pauseMora)
        }
        try container.encode(isInterrogative, forKey: .isInterrogative)
    }
}

struct RemoteMoraPayload: Codable, Equatable {
    var text: String
    var consonant: String?
    var consonantLength: Double?
    var vowel: String
    var vowelLength: Double
    var pitch: Double

    init(mora: Mora) {
        self.text = mora.text
        self.consonant = mora.consonant
        self.consonantLength = mora.consonantLength
        self.vowel = mora.vowel
        self.vowelLength = mora.vowelLength
        self.pitch = mora.pitch
    }

    var mora: Mora {
        Mora(
            text: text,
            consonant: consonant,
            consonantLength: consonantLength,
            vowel: vowel,
            vowelLength: vowelLength,
            pitch: pitch
        )
    }

    enum CodingKeys: String, CodingKey {
        case text
        case consonant
        case consonantLength = "consonant_length"
        case vowel
        case vowelLength = "vowel_length"
        case pitch
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        if let consonant {
            try container.encode(consonant, forKey: .consonant)
        } else {
            try container.encodeNil(forKey: .consonant)
        }
        if let consonantLength {
            try container.encode(consonantLength, forKey: .consonantLength)
        } else {
            try container.encodeNil(forKey: .consonantLength)
        }
        try container.encode(vowel, forKey: .vowel)
        try container.encode(vowelLength, forKey: .vowelLength)
        try container.encode(pitch, forKey: .pitch)
    }
}
