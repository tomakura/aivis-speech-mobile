import Foundation

enum AIVMXEmbeddedMetadataParser {
    private static let metadataFieldNumber: UInt64 = 14

    static func envelope(from data: Data) throws -> AIVMXMetadataEnvelope? {
        let rawMetadata = try extractMetadataProps(from: data)
        guard let manifestJSONString = rawMetadata["aivm_manifest"] else {
            return nil
        }

        let manifest = try JSONDecoder().decode(
            EmbeddedAivmManifest.self,
            from: Data(manifestJSONString.utf8)
        )
        let hyperParameters = rawMetadata["aivm_hyper_parameters"].flatMap { json in
            try? JSONDecoder().decode(
                EmbeddedStyleBertVITS2HyperParameters.self,
                from: Data(json.utf8)
            )
        }
        let styleVectors = rawMetadata["aivm_style_vectors"].flatMap { Data(base64Encoded: $0) }
        let styleIDs = manifest.speakers
            .flatMap(\.styles)
            .map(\.localID)

        return AIVMXMetadataEnvelope(
            manifest: AIVMXManifest(
                uuid: manifest.uuid,
                name: manifest.name,
                version: manifest.version,
                modelArchitecture: mapModelArchitecture(manifest.modelArchitecture),
                modelFormat: mapModelFormat(manifest.modelFormat),
                speakers: manifest.speakers.map { speaker in
                    AIVMXSpeakerManifest(
                        uuid: speaker.uuid,
                        name: speaker.name,
                        styles: speaker.styles.map { style in
                            AIVMXStyleManifest(localId: style.localID, name: style.name)
                        }
                    )
                },
                runtimeDescriptor: makeRuntimeDescriptor(
                    manifest: manifest,
                    hyperParameters: hyperParameters,
                    styleVectorPayload: styleVectors,
                    styleIDs: styleIDs
                )
            ),
            loadState: AIVMXLoadState(installed: true, loaded: false, active: false)
        )
    }

    private static func extractMetadataProps(from data: Data) throws -> [String: String] {
        var offset = 0
        var metadata: [String: String] = [:]

        while offset < data.count {
            let tag = try readVarint(from: data, offset: &offset)
            let fieldNumber = tag >> 3
            let wireType = Int(tag & 0x7)

            if fieldNumber == metadataFieldNumber, wireType == 2 {
                let entryData = try readLengthDelimited(from: data, offset: &offset)
                let (key, value) = try parseStringEntry(from: entryData)
                if !key.isEmpty {
                    metadata[key] = value
                }
            } else {
                try skipField(wireType: wireType, from: data, offset: &offset)
            }
        }

        return metadata
    }

    private static func parseStringEntry(from data: Data) throws -> (String, String) {
        var offset = 0
        var key = ""
        var value = ""

        while offset < data.count {
            let tag = try readVarint(from: data, offset: &offset)
            let fieldNumber = tag >> 3
            let wireType = Int(tag & 0x7)

            switch (fieldNumber, wireType) {
            case (1, 2):
                key = try readString(from: data, offset: &offset)
            case (2, 2):
                value = try readString(from: data, offset: &offset)
            default:
                try skipField(wireType: wireType, from: data, offset: &offset)
            }
        }

        return (key, value)
    }

    private static func readString(from data: Data, offset: inout Int) throws -> String {
        let valueData = try readLengthDelimited(from: data, offset: &offset)
        guard let string = String(data: valueData, encoding: .utf8) else {
            throw ParserError.invalidUTF8
        }
        return string
    }

    private static func readLengthDelimited(from data: Data, offset: inout Int) throws -> Data {
        let length = try Int(readVarint(from: data, offset: &offset))
        guard length >= 0, offset + length <= data.count else {
            throw ParserError.outOfBounds
        }
        let slice = data[offset..<(offset + length)]
        offset += length
        return Data(slice)
    }

    private static func readVarint(from data: Data, offset: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while offset < data.count {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
            if shift > 63 {
                throw ParserError.invalidVarint
            }
        }

        throw ParserError.outOfBounds
    }

    private static func skipField(wireType: Int, from data: Data, offset: inout Int) throws {
        switch wireType {
        case 0:
            _ = try readVarint(from: data, offset: &offset)
        case 1:
            guard offset + 8 <= data.count else { throw ParserError.outOfBounds }
            offset += 8
        case 2:
            _ = try readLengthDelimited(from: data, offset: &offset)
        case 5:
            guard offset + 4 <= data.count else { throw ParserError.outOfBounds }
            offset += 4
        default:
            throw ParserError.unsupportedWireType(wireType)
        }
    }

    private static func mapModelArchitecture(_ rawValue: String) -> AIVMXModelArchitecture {
        if rawValue == AIVMXModelArchitecture.styleBertVITS2JPExtra.rawValue {
            return .styleBertVITS2JPExtra
        }
        return .styleBertVITS2
    }

    private static func mapModelFormat(_ rawValue: String) -> AIVMXModelFormat {
        if rawValue == AIVMXModelFormat.onnx.rawValue {
            return .onnx
        }
        return .aivmx
    }

    private static func makeRuntimeDescriptor(
        manifest: EmbeddedAivmManifest,
        hyperParameters: EmbeddedStyleBertVITS2HyperParameters?,
        styleVectorPayload: Data?,
        styleIDs: [Int]
    ) -> ModelRuntimeDescriptor {
        let normalizedStyleIDs = Array(Set(styleIDs)).sorted()
        let vectorDimension = styleVectorPayload
            .flatMap(parseNumPyVectorDimension(from:))
            ?? hyperParameters?.model?.ginChannels
            ?? 256

        let styleProfiles = manifest.speakers.flatMap(\.styles).map { style in
            ModelStyleRuntimeMetadata(
                localID: style.localID,
                name: style.name,
                vectorDimension: vectorDimension,
                notes: [
                    "Imported from embedded AIVMX metadata_props.",
                ]
            )
        }

        var notes = [
            "Embedded AIVMX metadata extracted from ONNX metadata_props.",
        ]
        if hyperParameters == nil {
            notes.append("Hyper-parameters were not embedded in this package.")
        }
        if styleVectorPayload == nil {
            notes.append("Style vectors were not embedded in this package.")
        }

        return ModelRuntimeDescriptor(
            styleProfiles: styleProfiles,
            vectorProfiles: styleVectorPayload == nil
                ? []
                : [
                    ModelVectorRuntimeMetadata(
                        key: "aivm_style_vectors",
                        dimension: vectorDimension,
                        associatedStyleIDs: normalizedStyleIDs,
                        notes: [
                            "Decoded from embedded Base64 style vector payload.",
                        ]
                    )
                ],
            hyperParameters: ModelHyperParameterMetadata(
                outputSamplingRate: hyperParameters?.data?.samplingRate,
                outputStereo: false
            ),
            notes: notes
        )
    }

    private static func parseNumPyVectorDimension(from data: Data) -> Int? {
        let magic = Data([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59])
        guard data.count > 10, data.prefix(6) == magic else {
            return nil
        }

        let majorVersion = Int(data[6])
        let headerLengthRange: Range<Int>
        let headerLength: Int

        switch majorVersion {
        case 1:
            headerLengthRange = 8..<10
            headerLength = Int(UInt16(data[8]) | (UInt16(data[9]) << 8))
        case 2, 3:
            headerLengthRange = 8..<12
            let lower = UInt32(data[8])
            let midLow = UInt32(data[9]) << 8
            let midHigh = UInt32(data[10]) << 16
            let upper = UInt32(data[11]) << 24
            headerLength = Int(lower | midLow | midHigh | upper)
        default:
            return nil
        }

        let headerStart = headerLengthRange.upperBound
        let headerEnd = headerStart + headerLength
        guard headerEnd <= data.count else {
            return nil
        }

        guard let header = String(data: data[headerStart..<headerEnd], encoding: .ascii) else {
            return nil
        }

        guard let shapeRange = header.range(of: "shape': (") ?? header.range(of: "\"shape\": (") else {
            return nil
        }
        let remainder = header[shapeRange.upperBound...]
        guard let closeIndex = remainder.firstIndex(of: ")") else {
            return nil
        }

        let rawShape = remainder[..<closeIndex]
        let dimensions = rawShape
            .split(separator: ",")
            .compactMap { value in
                Int(value.trimmingCharacters(in: .whitespaces))
            }
        return dimensions.last
    }
}

private enum ParserError: Error {
    case outOfBounds
    case invalidVarint
    case invalidUTF8
    case unsupportedWireType(Int)
}

private struct EmbeddedAivmManifest: Decodable {
    var name: String
    var modelArchitecture: String
    var modelFormat: String
    var uuid: UUID
    var version: String
    var speakers: [EmbeddedAivmManifestSpeaker]

    enum CodingKeys: String, CodingKey {
        case name
        case modelArchitecture = "model_architecture"
        case modelFormat = "model_format"
        case uuid
        case version
        case speakers
    }
}

private struct EmbeddedAivmManifestSpeaker: Decodable {
    var name: String
    var uuid: UUID
    var styles: [EmbeddedAivmManifestStyle]
}

private struct EmbeddedAivmManifestStyle: Decodable {
    var name: String
    var localID: Int

    enum CodingKeys: String, CodingKey {
        case name
        case localID = "local_id"
    }
}

private struct EmbeddedStyleBertVITS2HyperParameters: Decodable {
    var data: EmbeddedStyleBertVITS2DataSection?
    var model: EmbeddedStyleBertVITS2ModelSection?
}

private struct EmbeddedStyleBertVITS2DataSection: Decodable {
    var samplingRate: Int?
    var style2id: [String: Int]?
    var spk2id: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case samplingRate = "sampling_rate"
        case style2id
        case spk2id
    }
}

private struct EmbeddedStyleBertVITS2ModelSection: Decodable {
    var ginChannels: Int?

    enum CodingKeys: String, CodingKey {
        case ginChannels = "gin_channels"
    }
}
