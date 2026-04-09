import Foundation

enum StyleBertVITS2TensorBuilder {
    static func makeInputs(
        contract: StyleBertVITS2InputContract,
        plan: StyleBertVITS2TensorPlan,
        featureResolution: StyleBertVITS2FeatureProvider.Resolution
    ) throws -> [String: ONNXTensorValue] {
        var inputs: [String: ONNXTensorValue] = [:]

        if let name = contract.phonemeIDsInputName {
            inputs[name] = .int64(plan.phonemeIDs, shape: [1, plan.phonemeCount])
        }
        if let name = contract.phonemeLengthsInputName {
            inputs[name] = .int64([Int64(plan.phonemeCount)], shape: [1])
        }
        if let name = contract.tonesInputName {
            inputs[name] = .int64(plan.tones, shape: [1, plan.tones.count])
        }
        if let name = contract.speakerIDInputName {
            inputs[name] = .int64([plan.speakerID], shape: [1])
        }
        if let name = contract.styleVectorInputName {
            inputs[name] = .float32(plan.styleVector, shape: [1, plan.styleVectorDimension])
        }
        if let name = contract.languageIDInputName {
            inputs[name] = .int64(plan.languageIDs, shape: [1, plan.languageIDs.count])
        }
        if let name = contract.lengthScaleInputName {
            inputs[name] = .float32([plan.lengthScale], shape: [])
        }
        if let name = contract.sdpRatioInputName {
            inputs[name] = .float32([plan.sdpRatio], shape: [])
        }
        if let name = contract.noiseScaleInputName {
            inputs[name] = .float32([plan.noiseScale], shape: [])
        }
        if let name = contract.noiseScaleWInputName {
            inputs[name] = .float32([plan.noiseScaleW], shape: [])
        }

        if case let .ready(features) = featureResolution {
            for (name, value) in features {
                inputs[name] = value
            }
        }

        return inputs
    }
}
