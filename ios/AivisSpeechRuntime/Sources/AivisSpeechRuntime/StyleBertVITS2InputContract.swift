import Foundation

struct StyleBertVITS2InputContract: Sendable, Equatable {
    let inputNames: [String]
    let outputNames: [String]

    let phonemeIDsInputName: String?
    let phonemeLengthsInputName: String?
    let tonesInputName: String?
    let speakerIDInputName: String?
    let styleVectorInputName: String?
    let bertInputName: String?
    let japaneseBertInputName: String?
    let englishBertInputName: String?
    let languageIDInputName: String?
    let lengthScaleInputName: String?
    let sdpRatioInputName: String?
    let noiseScaleInputName: String?
    let noiseScaleWInputName: String?

    init(inspection: ONNXModelInspection) {
        self.inputNames = inspection.inputNames
        self.outputNames = inspection.outputNames
        self.phonemeIDsInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["x_tst", "phones", "input_ids", "input"])
        self.phonemeLengthsInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["x_tst_lengths", "phone_lengths", "input_lengths"])
        self.tonesInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["tones", "tone", "x_tone", "prosody"])
        self.speakerIDInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["sid", "speaker_id", "speaker"])
        self.styleVectorInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["style_vec", "style_vector", "speaker_embedding", "spk_emb"])
        self.bertInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["bert"])
        self.japaneseBertInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["ja_bert"])
        self.englishBertInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["en_bert"])
        self.languageIDInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["lang_id", "language_id", "language"])
        self.lengthScaleInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["length_scale", "length"])
        self.sdpRatioInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["sdp_ratio"])
        self.noiseScaleInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["noise_scale"])
        self.noiseScaleWInputName = Self.firstMatch(in: inspection.inputNames, aliases: ["noise_scale_w"])
    }

    var isSampleSeedContract: Bool {
        Set(inputNames) == ["A", "B"] && Set(outputNames) == ["C"]
    }

    var requiresBERT: Bool {
        bertInputName != nil || japaneseBertInputName != nil || englishBertInputName != nil
    }

    var preferredWaveformOutputName: String? {
        if outputNames.count == 1 {
            return outputNames.first
        }
        return Self.firstMatch(in: outputNames, aliases: ["wave", "wav", "audio", "output", "y"])
    }

    var unresolvedRequiredInputNames: [String] {
        let resolved = Set(candidateInputNames.compactMap {
            $0
        })
        return inputNames.filter { !resolved.contains($0) }
    }

    var canBuildTensorPlan: Bool {
        phonemeIDsInputName != nil && phonemeLengthsInputName != nil && tonesInputName != nil
    }

    private var candidateInputNames: [String?] {
        [
            phonemeIDsInputName,
            phonemeLengthsInputName,
            tonesInputName,
            speakerIDInputName,
            styleVectorInputName,
            bertInputName,
            japaneseBertInputName,
            englishBertInputName,
            languageIDInputName,
            lengthScaleInputName,
            sdpRatioInputName,
            noiseScaleInputName,
            noiseScaleWInputName,
        ]
    }

    private static func firstMatch(in names: [String], aliases: [String]) -> String? {
        names.first { name in
            aliases.contains { alias in
                name.caseInsensitiveCompare(alias) == .orderedSame
            }
        }
    }
}
