import Foundation
import Testing
import AivisMobileCore
@testable import AivisSpeechRuntime

struct StyleBertVITS2ContractTests {
    @Test
    func inputContractRecognizesStyleBertAliases() {
        let inspection = ONNXModelInspection(
            inputNames: [
                "x_tst",
                "x_tst_lengths",
                "tones",
                "sid",
                "style_vec",
                "bert",
                "ja_bert",
                "lang_id",
                "length_scale",
                "sdp_ratio",
                "noise_scale",
                "noise_scale_w",
            ],
            outputNames: ["wave"]
        )

        let contract = StyleBertVITS2InputContract(inspection: inspection)

        #expect(contract.canBuildTensorPlan)
        #expect(contract.requiresBERT)
        #expect(contract.preferredWaveformOutputName == "wave")
        #expect(contract.unresolvedRequiredInputNames.isEmpty)
    }

    @Test
    func tensorPlannerBuildsPhonemeAndToneSequences() throws {
        let manifest = ModelManifest(
            uuid: UUID(),
            name: "Planner Test",
            version: "1.0.0",
            modelArchitecture: AIVMXModelArchitecture.styleBertVITS2.rawValue,
            modelFormat: AIVMXModelFormat.aivmx.rawValue,
            speakers: [
                ModelSpeaker(
                    uuid: UUID(),
                    name: "Speaker",
                    styles: [ModelStyle(localID: 0, name: "Normal")]
                )
            ],
            runtimeDescriptor: ModelRuntimeDescriptor(
                styleProfiles: [ModelStyleRuntimeMetadata(localID: 0, name: "Normal", vectorDimension: 128)],
                vectorProfiles: [ModelVectorRuntimeMetadata(key: "style_vec", dimension: 128, associatedStyleIDs: [0])],
                hyperParameters: ModelHyperParameterMetadata(outputSamplingRate: 44_100)
            )
        )
        let model = InstalledModel(
            id: UUID(),
            name: "Planner Test",
            version: "1.0.0",
            loadState: .active,
            localFileURL: URL(fileURLWithPath: "/tmp/test.onnx"),
            manifest: manifest
        )
        let query = AudioQuery(
            accentPhrases: [
                AccentPhrase(
                    moras: [
                        Mora(text: "テ", consonant: "t", consonantLength: 0.04, vowel: "e", vowelLength: 0.12, pitch: 1.0),
                        Mora(text: "ス", consonant: "s", consonantLength: 0.04, vowel: "u", vowelLength: 0.12, pitch: 0.8),
                        Mora(text: "ト", consonant: "t", consonantLength: 0.04, vowel: "o", vowelLength: 0.12, pitch: 0.6),
                    ],
                    accent: 2
                )
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
            kana: "テスト"
        )

        let plan = try StyleBertVITS2TensorPlanner.makePlan(
            query: query,
            styleID: 0,
            activeModel: model
        )

        #expect(plan.text == "テスト")
        #expect(plan.phonemeCount == 17)
        #expect(plan.phonemeIDs.count == plan.tones.count)
        #expect(plan.phonemeIDs.count == plan.languageIDs.count)
        #expect(plan.wordToPhonemeCounts.reduce(0, +) == plan.phonemeCount)
        #expect(plan.styleVectorDimension == 128)
        #expect(plan.speakerID == 0)
        #expect(plan.tones.contains(7))
        #expect(plan.tones.contains(0))
    }

    @Test
    func tensorPlannerUsesSpeakerIndexInsteadOfStyleIDForSidInput() throws {
        let manifest = ModelManifest(
            uuid: UUID(),
            name: "Multi Style Planner Test",
            version: "1.0.0",
            modelArchitecture: AIVMXModelArchitecture.styleBertVITS2.rawValue,
            modelFormat: AIVMXModelFormat.aivmx.rawValue,
            speakers: [
                ModelSpeaker(
                    uuid: UUID(),
                    name: "Speaker",
                    styles: [
                        ModelStyle(localID: 0, name: "Normal"),
                        ModelStyle(localID: 20, name: "Lazy Sad"),
                    ]
                )
            ],
            runtimeDescriptor: ModelRuntimeDescriptor(
                styleProfiles: [
                    ModelStyleRuntimeMetadata(localID: 0, name: "Normal", vectorDimension: 128),
                    ModelStyleRuntimeMetadata(localID: 20, name: "Lazy Sad", vectorDimension: 128),
                ],
                vectorProfiles: [
                    ModelVectorRuntimeMetadata(key: "style_vec", dimension: 128, associatedStyleIDs: [0, 20])
                ],
                hyperParameters: ModelHyperParameterMetadata(outputSamplingRate: 44_100)
            )
        )
        let model = InstalledModel(
            id: UUID(),
            name: "Multi Style Planner Test",
            version: "1.0.0",
            loadState: .active,
            localFileURL: URL(fileURLWithPath: "/tmp/test.onnx"),
            manifest: manifest
        )
        let query = AudioQuery(
            accentPhrases: [
                AccentPhrase(
                    moras: [
                        Mora(text: "テ", consonant: "t", consonantLength: 0.04, vowel: "e", vowelLength: 0.12, pitch: 1.0),
                        Mora(text: "ス", consonant: "s", consonantLength: 0.04, vowel: "u", vowelLength: 0.12, pitch: 0.8),
                    ],
                    accent: 1
                )
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
            kana: "テス"
        )

        let plan = try StyleBertVITS2TensorPlanner.makePlan(
            query: query,
            styleID: 20,
            activeModel: model
        )

        #expect(plan.speakerID == 0)
        #expect(plan.styleID == 20)
    }
}
