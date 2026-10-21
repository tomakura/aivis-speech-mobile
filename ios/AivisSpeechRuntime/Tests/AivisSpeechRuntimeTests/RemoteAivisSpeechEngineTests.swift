import Foundation
import Testing
@testable import AivisSpeechRuntime

struct RemoteAivisSpeechEngineTests {
    @Test
    func configuredBaseURLRequiresExplicitDevelopmentOverride() {
        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: RemoteAivisSpeechEngine.enabledUserDefaultsKey)
        let previousURL = defaults.object(forKey: RemoteAivisSpeechEngine.userDefaultsKey)
        defer {
            if let previousEnabled {
                defaults.set(previousEnabled, forKey: RemoteAivisSpeechEngine.enabledUserDefaultsKey)
            } else {
                defaults.removeObject(forKey: RemoteAivisSpeechEngine.enabledUserDefaultsKey)
            }
            if let previousURL {
                defaults.set(previousURL, forKey: RemoteAivisSpeechEngine.userDefaultsKey)
            } else {
                defaults.removeObject(forKey: RemoteAivisSpeechEngine.userDefaultsKey)
            }
        }

        defaults.set("http://192.168.1.42:10102", forKey: RemoteAivisSpeechEngine.userDefaultsKey)
        defaults.set(false, forKey: RemoteAivisSpeechEngine.enabledUserDefaultsKey)
        #expect(RemoteAivisSpeechEngine.configuredBaseURL == nil)

        defaults.set(true, forKey: RemoteAivisSpeechEngine.enabledUserDefaultsKey)
        #expect(RemoteAivisSpeechEngine.configuredBaseURL?.absoluteString == "http://192.168.1.42:10102")
    }

    @Test
    func remoteSpeakerPayloadDecodesGeneratedStyleIDs() throws {
        let data = """
        [
          {
            "name": "Flow_V4.0_Low",
            "speaker_uuid": "80e4b821-590e-4c63-bafe-2f9e662edec4",
            "styles": [
              {"name": "ノーマル", "id": 1530858848, "type": "talk"},
              {"name": "01_JOY", "id": 1530858849, "type": "talk"}
            ]
          }
        ]
        """.data(using: .utf8)!

        let speakers = try JSONDecoder().decode([RemoteSpeakerPayload].self, from: data)

        #expect(speakers.first?.name == "Flow_V4.0_Low")
        #expect(speakers.first?.styles[1].id == 1_530_858_849)
    }

    @Test
    func audioQueryPayloadDecodesAivisSpeechMixedJSONKeys() throws {
        let data = """
        {
          "accent_phrases": [
            {
              "moras": [
                {
                  "text": "キョ",
                  "consonant": "ky",
                  "consonant_length": 0.0,
                  "vowel": "o",
                  "vowel_length": 0.0,
                  "pitch": 0.0
                }
              ],
              "accent": 1,
              "pause_mora": null,
              "is_interrogative": false
            }
          ],
          "speedScale": 1.0,
          "intonationScale": 1.0,
          "tempoDynamicsScale": 1.0,
          "pitchScale": 0.0,
          "volumeScale": 1.0,
          "prePhonemeLength": 0.1,
          "postPhonemeLength": 0.1,
          "pauseLength": null,
          "pauseLengthScale": 1.0,
          "outputSamplingRate": 44100,
          "outputStereo": false,
          "kana": "今日はテストです"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(RemoteAudioQueryPayload.self, from: data)
        let query = payload.audioQuery

        #expect(query.kana == "今日はテストです")
        #expect(query.accentPhrases.first?.moras.first?.text == "キョ")
        #expect(query.accentPhrases.first?.moras.first?.consonant == "ky")
        #expect(query.outputSamplingRate == .explicit(44_100))
    }

    @Test
    func audioQueryPayloadEncodesAivisSpeechMixedJSONKeys() throws {
        let payload = RemoteAudioQueryPayload(
            audioQuery: .init(
                accentPhrases: [
                    .init(
                        moras: [
                            .init(
                                text: "テ",
                                consonant: "t",
                                consonantLength: 0.0,
                                vowel: "e",
                                vowelLength: 0.0,
                                pitch: 0.0
                            ),
                        ],
                        accent: 1,
                        pauseMora: nil,
                        isInterrogative: false
                    ),
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
                outputStereo: false,
                kana: "テストです"
            )
        )

        let data = try JSONEncoder().encode(payload)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let phrases = try #require(json["accent_phrases"] as? [[String: Any]])
        let firstPhrase = try #require(phrases.first)
        let moras = try #require(firstPhrase["moras"] as? [[String: Any]])
        let firstMora = try #require(moras.first)

        #expect(json["speedScale"] as? Double == 1.0)
        #expect(json["outputSamplingRate"] as? Int == 44_100)
        #expect(firstPhrase.keys.contains("pause_mora"))
        #expect(firstPhrase.keys.contains("is_interrogative"))
        #expect(firstMora.keys.contains("consonant_length"))
        #expect(firstMora.keys.contains("vowel_length"))
    }
}
