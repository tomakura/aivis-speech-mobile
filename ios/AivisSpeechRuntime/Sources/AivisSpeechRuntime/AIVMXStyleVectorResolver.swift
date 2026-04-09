import Foundation
import AivisMobileCore

enum AIVMXStyleVectorResolver {
    private static let metadataFieldNumber: UInt64 = 14

    static func resolveVector(
        styleID: Int,
        modelURL: URL?,
        manifest: ModelManifest,
        expectedDimension: Int
    ) -> [Float]? {
        guard let modelURL,
              let data = try? Data(contentsOf: modelURL),
              let metadata = try? extractMetadataProps(from: data),
              let encodedVectors = metadata["aivm_style_vectors"],
              let vectorData = Data(base64Encoded: encodedVectors),
              let matrix = decodeStyleVectorMatrix(from: vectorData) else {
            return nil
        }

        let styleOrder = manifest.speakers.flatMap(\.styles).map(\.localID)
        guard let rowIndex = styleOrder.firstIndex(of: styleID), rowIndex < matrix.count else {
            return nil
        }

        let vector = matrix[rowIndex]
        if vector.count == expectedDimension {
            return vector
        }
        if vector.count > expectedDimension {
            return Array(vector.prefix(expectedDimension))
        }

        return vector + Array(repeating: Float.zero, count: expectedDimension - vector.count)
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

    private static func decodeStyleVectorMatrix(from npyData: Data) -> [[Float]]? {
        let header = try? parseNPYHeader(from: npyData)
        guard let header, header.shape.count == 2 else {
            return nil
        }

        let rowCount = header.shape[0]
        let columnCount = header.shape[1]
        let floatCount = rowCount * columnCount
        let dataRange = header.dataOffset..<(header.dataOffset + floatCount * MemoryLayout<Float>.stride)
        guard dataRange.upperBound <= npyData.count else {
            return nil
        }

        let values: [Float] = npyData[dataRange].withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
        guard values.count >= floatCount else {
            return nil
        }

        var matrix: [[Float]] = []
        matrix.reserveCapacity(rowCount)
        for rowIndex in 0..<rowCount {
            let start = rowIndex * columnCount
            matrix.append(Array(values[start..<(start + columnCount)]))
        }
        return matrix
    }

    private static func parseNPYHeader(from data: Data) throws -> (shape: [Int], dataOffset: Int) {
        let magic = Data([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59])
        guard data.count > 10, data.prefix(6) == magic else {
            throw ParserError.invalidUTF8
        }

        let majorVersion = Int(data[6])
        let headerLength: Int
        let headerStart: Int

        switch majorVersion {
        case 1:
            headerLength = Int(UInt16(data[8]) | (UInt16(data[9]) << 8))
            headerStart = 10
        case 2, 3:
            headerLength = Int(UInt32(data[8]) | (UInt32(data[9]) << 8) | (UInt32(data[10]) << 16) | (UInt32(data[11]) << 24))
            headerStart = 12
        default:
            throw ParserError.invalidVarint
        }

        let headerEnd = headerStart + headerLength
        guard headerEnd <= data.count,
              let header = String(data: data[headerStart..<headerEnd], encoding: .ascii) else {
            throw ParserError.invalidUTF8
        }

        guard let shapeRange = header.range(of: "shape': (") else {
            throw ParserError.invalidUTF8
        }
        let remainder = header[shapeRange.upperBound...]
        guard let closeIndex = remainder.firstIndex(of: ")") else {
            throw ParserError.invalidUTF8
        }

        let dimensions = remainder[..<closeIndex]
            .split(separator: ",")
            .compactMap { value in
                Int(value.trimmingCharacters(in: .whitespaces))
            }
        return (dimensions, headerEnd)
    }
}

private enum ParserError: Error {
    case outOfBounds
    case invalidVarint
    case invalidUTF8
    case unsupportedWireType(Int)
}
