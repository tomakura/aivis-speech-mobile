import Foundation

public enum ScalarInputMode: String, Sendable, Hashable {
    case rank0Scalar
    case rank1SingleElement
}

public struct StaticShapeProfile: Sendable, Hashable, Equatable {
    public struct DimensionOverride: Sendable, Hashable, Equatable {
        public var name: String
        public var value: Int

        public init(name: String, value: Int) {
            self.name = name
            self.value = value
        }
    }

    public var label: String
    public var dimensions: [DimensionOverride]

    public init(label: String, dimensions: [DimensionOverride]) {
        self.label = label
        self.dimensions = dimensions.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name
        }
    }

    public subscript(name: String) -> Int? {
        dimensions.first(where: { $0.name == name })?.value
    }

    public var shapeLabel: String {
        label
    }
}

enum BucketedShapePlanner {
    private static let bertBuckets = [8, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512]
    private static let acousticBuckets = [16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]

    static func bucketedLength(for length: Int, buckets: [Int]) -> Int {
        let normalized = max(1, length)
        if let bucket = buckets.first(where: { normalized <= $0 }) {
            return bucket
        }
        return normalized
    }

    static func bertProfile(forTokenCount tokenCount: Int) -> StaticShapeProfile {
        let bucket = bucketedLength(for: tokenCount, buckets: bertBuckets)
        return StaticShapeProfile(
            label: "bert-\(bucket)",
            dimensions: [
                .init(name: "batch_size", value: 1),
                .init(name: "sequence_length", value: bucket),
            ]
        )
    }

    static func acousticProfile(
        forPhonemeCount phonemeCount: Int,
        styleVectorDimension: Int? = nil
    ) -> StaticShapeProfile {
        let bucket = bucketedLength(for: phonemeCount, buckets: acousticBuckets)
        var dimensions: [StaticShapeProfile.DimensionOverride] = [
            .init(name: "batch_size", value: 1),
            .init(name: "x_tst_max_length", value: bucket),
        ]
        if let styleVectorDimension {
            dimensions.append(.init(name: "style_vector_length", value: styleVectorDimension))
        }
        return StaticShapeProfile(
            label: styleVectorDimension.map { "acoustic-\(bucket)-sv\($0)" } ?? "acoustic-\(bucket)",
            dimensions: dimensions
        )
    }

    static func paddedInput(
        named inputName: String,
        value: ONNXTensorValue,
        profile: StaticShapeProfile?,
        scalarInputMode: ScalarInputMode
    ) -> ONNXTensorValue {
        switch value {
        case let .float32(values, shape):
            if shape.isEmpty {
                return scalarInputMode == .rank0Scalar
                    ? .float32(values, shape: [])
                    : .float32(values, shape: [1])
            }
            guard let targetLength = targetLength(for: inputName, profile: profile) else {
                return value
            }
            return .float32(
                pad(values, shape: shape, toLastDimension: targetLength),
                shape: replacingLastDimension(of: shape, with: targetLength)
            )
        case let .int32(values, shape):
            if shape.isEmpty {
                return scalarInputMode == .rank0Scalar
                    ? .int32(values, shape: [])
                    : .int32(values, shape: [1])
            }
            guard let targetLength = targetLength(for: inputName, profile: profile) else {
                return value
            }
            return .int32(
                pad(values, shape: shape, toLastDimension: targetLength),
                shape: replacingLastDimension(of: shape, with: targetLength)
            )
        case let .int64(values, shape):
            if shape.isEmpty {
                return scalarInputMode == .rank0Scalar
                    ? .int64(values, shape: [])
                    : .int64(values, shape: [1])
            }
            guard let targetLength = targetLength(for: inputName, profile: profile) else {
                return value
            }
            return .int64(
                pad(values, shape: shape, toLastDimension: targetLength),
                shape: replacingLastDimension(of: shape, with: targetLength)
            )
        case .strings:
            return value
        }
    }

    private static func targetLength(for inputName: String, profile: StaticShapeProfile?) -> Int? {
        guard let profile else { return nil }
        let lowered = inputName.lowercased()
        if ["x_tst", "tones", "language", "lang_id", "language_id", "bert", "ja_bert", "en_bert"].contains(lowered) {
            return profile["x_tst_max_length"] ?? profile["sequence_length"]
        }
        if ["input_ids", "attention_mask", "token_type_ids"].contains(lowered) {
            return profile["sequence_length"]
        }
        return nil
    }

    private static func replacingLastDimension(of shape: [Int], with value: Int) -> [Int] {
        guard !shape.isEmpty else { return shape }
        var shape = shape
        shape[shape.count - 1] = value
        return shape
    }

    private static func pad<T>(_ values: [T], shape: [Int], toLastDimension targetLength: Int) -> [T] where T: BinaryInteger {
        padGeneric(values, shape: shape, toLastDimension: targetLength, fill: .zero)
    }

    private static func pad<T>(_ values: [T], shape: [Int], toLastDimension targetLength: Int) -> [T] where T: BinaryFloatingPoint {
        padGeneric(values, shape: shape, toLastDimension: targetLength, fill: .zero)
    }

    private static func padGeneric<T>(_ values: [T], shape: [Int], toLastDimension targetLength: Int, fill: T) -> [T] {
        guard targetLength > 0 else { return values }
        guard let currentLength = shape.last, currentLength < targetLength else { return values }
        let prefixCount = max(1, shape.dropLast().reduce(1, *))
        guard prefixCount * currentLength == values.count else { return values }

        let planeSize = currentLength
        let paddedPlaneSize = targetLength
        var padded = Array(repeating: fill, count: prefixCount * paddedPlaneSize)
        for prefixIndex in 0..<prefixCount {
            let sourceBase = prefixIndex * planeSize
            let destinationBase = prefixIndex * paddedPlaneSize
            for offset in 0..<planeSize {
                padded[destinationBase + offset] = values[sourceBase + offset]
            }
        }
        return padded
    }
}
