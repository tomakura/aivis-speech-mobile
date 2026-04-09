import Foundation
import OnnxRuntimeBindings

public enum ONNXModelRunnerError: LocalizedError {
    case unsupportedTensorType(ORTTensorElementDataType)
    case invalidTensorData(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedTensorType(elementType):
            return "Unsupported ORT tensor type: \(elementType.rawValue)"
        case let .invalidTensorData(message):
            return "Invalid tensor data: \(message)"
        }
    }
}

public enum ONNXTensorValue: Sendable, Equatable {
    case float32([Float], shape: [Int])
    case int32([Int32], shape: [Int])
    case int64([Int64], shape: [Int])
    case strings([String], shape: [Int])

    var shapeNumbers: [NSNumber] {
        shape.map(NSNumber.init(value:))
    }

    var shape: [Int] {
        switch self {
        case let .float32(_, shape), let .int32(_, shape), let .int64(_, shape), let .strings(_, shape):
            return shape
        }
    }

    func makeORTValue() throws -> ORTValue {
        switch self {
        case let .float32(values, shape):
            var values = values
            let data = NSMutableData(bytes: &values, length: values.count * MemoryLayout<Float>.stride)
            return try ORTValue(
                tensorData: data,
                elementType: .float,
                shape: shape.map(NSNumber.init(value:))
            )
        case let .int32(values, shape):
            var values = values
            let data = NSMutableData(bytes: &values, length: values.count * MemoryLayout<Int32>.stride)
            return try ORTValue(
                tensorData: data,
                elementType: .int32,
                shape: shape.map(NSNumber.init(value:))
            )
        case let .int64(values, shape):
            var values = values
            let data = NSMutableData(bytes: &values, length: values.count * MemoryLayout<Int64>.stride)
            return try ORTValue(
                tensorData: data,
                elementType: .int64,
                shape: shape.map(NSNumber.init(value:))
            )
        case let .strings(values, shape):
            return try ORTValue(tensorStringData: values, shape: shape.map(NSNumber.init(value:)))
        }
    }

    static func fromORTValue(_ ortValue: ORTValue) throws -> ONNXTensorValue {
        let tensorInfo = try ortValue.tensorTypeAndShapeInfo()
        let shape = tensorInfo.shape.map(\.intValue)

        switch tensorInfo.elementType {
        case .float:
            let data = try ortValue.tensorData()
            let count = data.length / MemoryLayout<Float>.stride
            let values = (data as Data).withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self).prefix(count))
            }
            return .float32(values, shape: shape)
        case .int32:
            let data = try ortValue.tensorData()
            let count = data.length / MemoryLayout<Int32>.stride
            let values = (data as Data).withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Int32.self).prefix(count))
            }
            return .int32(values, shape: shape)
        case .int64:
            let data = try ortValue.tensorData()
            let count = data.length / MemoryLayout<Int64>.stride
            let values = (data as Data).withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Int64.self).prefix(count))
            }
            return .int64(values, shape: shape)
        case .string:
            let values = try ortValue.tensorStringData()
            return .strings(values, shape: shape)
        default:
            throw ONNXModelRunnerError.unsupportedTensorType(tensorInfo.elementType)
        }
    }
}

public enum ONNXModelRunner {
    public static func run(
        modelURL: URL,
        inputs: [String: ONNXTensorValue],
        outputNames: Set<String>? = nil,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar
    ) throws -> [String: ONNXTensorValue] {
        let session = try ONNXRuntimeSupport.cachedSession(
            for: modelURL,
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode
        )

        var ortInputs: [String: ORTValue] = [:]
        for (name, value) in inputs {
            let paddedValue = BucketedShapePlanner.paddedInput(
                named: name,
                value: value,
                profile: shapeProfile,
                scalarInputMode: scalarInputMode
            )
            ortInputs[name] = try paddedValue.makeORTValue()
        }

        let requestedOutputNames: Set<String>
        if let outputNames {
            requestedOutputNames = outputNames
        } else {
            requestedOutputNames = Set(try session.outputNames())
        }
        let ortOutputs = try session.run(
            withInputs: ortInputs,
            outputNames: requestedOutputNames,
            runOptions: nil
        )

        var decodedOutputs: [String: ONNXTensorValue] = [:]
        for (name, value) in ortOutputs {
            decodedOutputs[name] = try ONNXTensorValue.fromORTValue(value)
        }
        return decodedOutputs
    }
}
