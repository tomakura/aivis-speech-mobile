import Foundation
import Testing
@testable import AivisSpeechRuntime

struct RuntimeShapeRegressionTests {
    @Test
    func sessionCacheBucketsStaticShapeAndProviderVariantsSeparately() throws {
        let modelURL = URL(fileURLWithPath: "/tmp/runtime-shape-regression.onnx")
        let cache = ONNXSessionCache { url, preferCoreML, staticInputShapesOnly, shapeProfile, scalarInputMode in
            ONNXSessionHandle.placeholder(
                modelURL: url,
                preferredExecutionProvider: preferCoreML ? "CoreML Execution Provider" : "CPU fallback",
                staticInputShapesOnly: staticInputShapesOnly,
                shapeProfile: shapeProfile,
                scalarInputMode: scalarInputMode
            )
        }

        let dynamicCoreML = try cache.sessionHandle(
            for: modelURL,
            preferCoreML: true,
            staticInputShapesOnly: false
        )
        let staticCoreML = try cache.sessionHandle(
            for: modelURL,
            preferCoreML: true,
            staticInputShapesOnly: true
        )
        let dynamicCPU = try cache.sessionHandle(
            for: modelURL,
            preferCoreML: false,
            staticInputShapesOnly: false
        )

        #expect(dynamicCoreML !== staticCoreML)
        #expect(dynamicCoreML !== dynamicCPU)
        #expect(staticCoreML !== dynamicCPU)
        #expect(cache.cachedSessionCount() == 3)
    }

    @Test
    func invalidatingOneSessionBucketDoesNotPolluteSiblingKeys() throws {
        let modelURL = URL(fileURLWithPath: "/tmp/runtime-shape-regression.onnx")
        let cache = ONNXSessionCache { url, preferCoreML, staticInputShapesOnly, shapeProfile, scalarInputMode in
            ONNXSessionHandle.placeholder(
                modelURL: url,
                preferredExecutionProvider: preferCoreML ? "CoreML Execution Provider" : "CPU fallback",
                staticInputShapesOnly: staticInputShapesOnly,
                shapeProfile: shapeProfile,
                scalarInputMode: scalarInputMode
            )
        }

        _ = try cache.sessionHandle(for: modelURL, preferCoreML: true, staticInputShapesOnly: false)
        let staticCoreML = try cache.sessionHandle(for: modelURL, preferCoreML: true, staticInputShapesOnly: true)

        cache.invalidateSession(for: modelURL, preferCoreML: true, staticInputShapesOnly: false)

        #expect(cache.cachedSessionCount() == 1)
        let survivingHandle = try cache.sessionHandle(for: modelURL, preferCoreML: true, staticInputShapesOnly: true)
        #expect(staticCoreML === survivingHandle)
    }

    @Test
    func invalidatingSessionsForModelDropsAllShapeAwareBuckets() throws {
        let modelURL = URL(fileURLWithPath: "/tmp/runtime-shape-regression.onnx")
        let cache = ONNXSessionCache { url, preferCoreML, staticInputShapesOnly, shapeProfile, scalarInputMode in
            ONNXSessionHandle.placeholder(
                modelURL: url,
                preferredExecutionProvider: preferCoreML ? "CoreML Execution Provider" : "CPU fallback",
                staticInputShapesOnly: staticInputShapesOnly,
                shapeProfile: shapeProfile,
                scalarInputMode: scalarInputMode
            )
        }
        let small = StaticShapeProfile(label: "acoustic-64", dimensions: [.init(name: "x_tst_max_length", value: 64)])
        let large = StaticShapeProfile(label: "acoustic-128", dimensions: [.init(name: "x_tst_max_length", value: 128)])

        _ = try cache.sessionHandle(for: modelURL, preferCoreML: true, staticInputShapesOnly: true, shapeProfile: small)
        _ = try cache.sessionHandle(for: modelURL, preferCoreML: true, staticInputShapesOnly: true, shapeProfile: large)

        cache.invalidateSessions(for: modelURL)

        #expect(cache.cachedSessionCount() == 0)
    }

    @Test
    func tensorBuilderKeepsScalarInputsRankZeroWhileLengthsStayRankOne() throws {
        let inputs = try StyleBertVITS2TensorBuilder.makeInputs(
            contract: makeAcousticContract(),
            plan: makeTensorPlan(),
            featureResolution: .ready([:])
        )

        let phonemeLengths = try #require(inputs["x_tst_lengths"])
        let speakerID = try #require(inputs["sid"])
        let lengthScale = try #require(inputs["length_scale"])
        let sdpRatio = try #require(inputs["sdp_ratio"])
        let noiseScale = try #require(inputs["noise_scale"])
        let noiseScaleW = try #require(inputs["noise_scale_w"])

        #expect(extractShape(from: phonemeLengths) == [1])
        #expect(extractShape(from: speakerID) == [1])
        #expect(extractShape(from: lengthScale) == [])
        #expect(extractShape(from: sdpRatio) == [])
        #expect(extractShape(from: noiseScale) == [])
        #expect(extractShape(from: noiseScaleW) == [])
    }

    @Test
    func tensorBuilderPreservesSeparateBertAndAcousticShapes() throws {
        let plan = makeTensorPlan(phonemeCount: 9, styleVectorDimension: 128)
        let hiddenSize = 1024
        let features = ONNXTensorValue.float32(
            Array(repeating: 0.25, count: hiddenSize * plan.phonemeCount),
            shape: [1, hiddenSize, plan.phonemeCount]
        )

        let inputs = try StyleBertVITS2TensorBuilder.makeInputs(
            contract: makeAcousticContract(includeBertInputs: true),
            plan: plan,
            featureResolution: .ready([
                "ja_bert": features,
                "bert": ONNXTensorValue.float32(
                    Array(repeating: 0, count: hiddenSize * plan.phonemeCount),
                    shape: [1, hiddenSize, plan.phonemeCount]
                ),
            ])
        )

        #expect(extractShape(from: try #require(inputs["x_tst"])) == [1, plan.phonemeCount])
        #expect(extractShape(from: try #require(inputs["tones"])) == [1, plan.phonemeCount])
        #expect(extractShape(from: try #require(inputs["lang_id"])) == [1, plan.phonemeCount])
        #expect(extractShape(from: try #require(inputs["style_vec"])) == [1, plan.styleVectorDimension])
        #expect(extractShape(from: try #require(inputs["ja_bert"])) == [1, hiddenSize, plan.phonemeCount])
        #expect(extractShape(from: try #require(inputs["bert"])) == [1, hiddenSize, plan.phonemeCount])
    }

    @Test
    func sessionCacheSeparatesShapeProfiles() throws {
        let modelURL = URL(fileURLWithPath: "/tmp/runtime-shape-regression.onnx")
        let cache = ONNXSessionCache { url, preferCoreML, staticInputShapesOnly, shapeProfile, scalarInputMode in
            ONNXSessionHandle.placeholder(
                modelURL: url,
                preferredExecutionProvider: preferCoreML ? "CoreML Execution Provider" : "CPU fallback",
                staticInputShapesOnly: staticInputShapesOnly,
                shapeProfile: shapeProfile,
                scalarInputMode: scalarInputMode
            )
        }
        let small = StaticShapeProfile(label: "acoustic-64", dimensions: [.init(name: "x_tst_max_length", value: 64)])
        let large = StaticShapeProfile(label: "acoustic-128", dimensions: [.init(name: "x_tst_max_length", value: 128)])

        let first = try cache.sessionHandle(for: modelURL, preferCoreML: true, staticInputShapesOnly: true, shapeProfile: small)
        let second = try cache.sessionHandle(for: modelURL, preferCoreML: true, staticInputShapesOnly: true, shapeProfile: large)

        #expect(first !== second)
        #expect(cache.cachedSessionCount() == 2)
    }

    @Test
    func bucketPlannerPadsSequenceInputsWithoutChangingScalars() {
        let profile = StaticShapeProfile(
            label: "acoustic-16",
            dimensions: [.init(name: "x_tst_max_length", value: 16)]
        )

        let paddedPhones = BucketedShapePlanner.paddedInput(
            named: "x_tst",
            value: .int64([1, 2, 3, 4], shape: [1, 4]),
            profile: profile,
            scalarInputMode: .rank0Scalar
        )
        let paddedBert = BucketedShapePlanner.paddedInput(
            named: "bert",
            value: .float32(Array(repeating: 1, count: 8), shape: [1, 2, 4]),
            profile: profile,
            scalarInputMode: .rank0Scalar
        )
        let paddedLangID = BucketedShapePlanner.paddedInput(
            named: "lang_id",
            value: .int64([1, 1, 1, 1], shape: [1, 4]),
            profile: profile,
            scalarInputMode: .rank0Scalar
        )
        let scalar = BucketedShapePlanner.paddedInput(
            named: "length_scale",
            value: .float32([1.0], shape: []),
            profile: profile,
            scalarInputMode: .rank0Scalar
        )

        #expect(extractShape(from: paddedPhones) == [1, 16])
        #expect(extractShape(from: paddedBert) == [1, 2, 16])
        #expect(extractShape(from: paddedLangID) == [1, 16])
        #expect(extractShape(from: scalar) == [])
    }
}

private func makeAcousticContract(includeBertInputs: Bool = false) -> StyleBertVITS2InputContract {
    var inputNames = [
        "x_tst",
        "x_tst_lengths",
        "tones",
        "sid",
        "style_vec",
        "lang_id",
        "length_scale",
        "sdp_ratio",
        "noise_scale",
        "noise_scale_w",
    ]
    if includeBertInputs {
        inputNames.append(contentsOf: ["bert", "ja_bert"])
    }
    return StyleBertVITS2InputContract(
        inspection: ONNXModelInspection(
            inputNames: inputNames,
            outputNames: ["wave"]
        )
    )
}

private func makeTensorPlan(
    phonemeCount: Int = 7,
    styleVectorDimension: Int = 64
) -> StyleBertVITS2TensorPlan {
    let phonemeIDs = Array(repeating: Int64(4), count: phonemeCount)
    let tones = Array(repeating: Int64(7), count: phonemeCount)
    let languageIDs = Array(repeating: Int64(1), count: phonemeCount)

    return StyleBertVITS2TensorPlan(
        text: "テスト",
        wordToPhonemeCounts: [phonemeCount],
        phonemeSymbols: Array(repeating: "a", count: phonemeCount),
        phonemeIDs: phonemeIDs,
        tones: tones,
        languageIDs: languageIDs,
        phonemeCount: phonemeCount,
        speakerID: 0,
        styleID: 0,
        styleVector: Array(repeating: 0.5, count: styleVectorDimension),
        styleVectorDimension: styleVectorDimension,
        lengthScale: 1.0,
        sdpRatio: 0.2,
        noiseScale: 0.6,
        noiseScaleW: 0.8,
        outputSampleRate: 44_100
    )
}

private func extractShape(from value: ONNXTensorValue) -> [Int] {
    switch value {
    case let .float32(_, shape):
        shape
    case let .int32(_, shape):
        shape
    case let .int64(_, shape):
        shape
    case let .strings(_, shape):
        shape
    }
}
