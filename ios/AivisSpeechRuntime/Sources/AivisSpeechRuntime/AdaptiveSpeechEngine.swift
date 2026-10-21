import Foundation
import AivisMobileCore

public actor AdaptiveSpeechEngine: SpeechEngine {
    private let primary: any SpeechEngine

    public init(primary: any SpeechEngine) {
        self.primary = primary
    }

    public func supportedDevices() async throws -> SupportedDevices {
        try await primary.supportedDevices()
    }

    public func makeAudioQuery(text: String, styleID: Int) async throws -> AudioQuery {
        try await primary.makeAudioQuery(text: text, styleID: styleID)
    }

    public func synthesize(query: AudioQuery, styleID: Int) async throws -> Data {
        try await primary.synthesize(query: query, styleID: styleID)
    }
}
