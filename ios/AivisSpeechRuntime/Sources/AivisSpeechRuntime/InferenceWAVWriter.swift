import Foundation

enum InferenceWAVWriterError: LocalizedError {
    case unsupportedTensorShape([Int])
    case unsupportedTensorValue
    case invalidSampleRate(Int)
    case silentWaveform
    case invalidWAVData

    var errorDescription: String? {
        switch self {
        case let .unsupportedTensorShape(shape):
            return "Unsupported waveform tensor shape: \(shape)."
        case .unsupportedTensorValue:
            return "The inference output could not be converted to waveform samples."
        case let .invalidSampleRate(sampleRate):
            return "Invalid sample rate: \(sampleRate)."
        case .silentWaveform:
            return "合成結果の波形が無音です。WAVは書き出していません。"
        case .invalidWAVData:
            return "生成済みWAVデータを結合できませんでした。"
        }
    }
}

enum InferenceWAVWriter {
    static func makeWAVData(
        from value: ONNXTensorValue,
        sampleRate: Int,
        stereo: Bool = false
    ) throws -> Data {
        guard sampleRate > 0 else {
            throw InferenceWAVWriterError.invalidSampleRate(sampleRate)
        }

        let samples = try normalizedSamples(from: value)
        let channelCount = stereo ? 2 : 1
        var pcm = Data()
        pcm.reserveCapacity(samples.count * channelCount * MemoryLayout<Int16>.size)

        var maxPCMAmplitude = 0
        for sample in samples {
            let int16 = clampedSample(sample)
            maxPCMAmplitude = max(maxPCMAmplitude, Int(abs(Int32(int16))))
            pcm.append(contentsOf: int16.leBytes)
            if stereo {
                pcm.append(contentsOf: int16.leBytes)
            }
        }

        guard maxPCMAmplitude > 0 else {
            throw InferenceWAVWriterError.silentWaveform
        }

        let byteRate = sampleRate * channelCount * MemoryLayout<Int16>.size
        let blockAlign = channelCount * MemoryLayout<Int16>.size
        let dataChunkSize = pcm.count
        let riffChunkSize = 36 + dataChunkSize

        var wav = Data()
        wav.reserveCapacity(44 + dataChunkSize)
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendLittleEndian(UInt32(riffChunkSize))
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt16(channelCount))
        wav.appendLittleEndian(UInt32(sampleRate))
        wav.appendLittleEndian(UInt32(byteRate))
        wav.appendLittleEndian(UInt16(blockAlign))
        wav.appendLittleEndian(UInt16(16))
        wav.append(contentsOf: "data".utf8)
        wav.appendLittleEndian(UInt32(dataChunkSize))
        wav.append(pcm)
        return wav
    }

    static func concatenateWAVData(_ wavs: [Data]) throws -> Data {
        guard let first = wavs.first else {
            throw InferenceWAVWriterError.invalidWAVData
        }
        let firstHeader = try parseWAVHeader(first)
        var pcm = Data()
        for wav in wavs {
            let header = try parseWAVHeader(wav)
            guard header.sampleRate == firstHeader.sampleRate,
                  header.channelCount == firstHeader.channelCount,
                  header.bitsPerSample == firstHeader.bitsPerSample else {
                throw InferenceWAVWriterError.invalidWAVData
            }
            pcm.append(wav.subdata(in: header.dataRange))
        }

        let byteRate = firstHeader.sampleRate * firstHeader.channelCount * MemoryLayout<Int16>.size
        let blockAlign = firstHeader.channelCount * MemoryLayout<Int16>.size
        let riffChunkSize = 36 + pcm.count

        var wav = Data()
        wav.reserveCapacity(44 + pcm.count)
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendLittleEndian(UInt32(riffChunkSize))
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt16(firstHeader.channelCount))
        wav.appendLittleEndian(UInt32(firstHeader.sampleRate))
        wav.appendLittleEndian(UInt32(byteRate))
        wav.appendLittleEndian(UInt16(blockAlign))
        wav.appendLittleEndian(UInt16(firstHeader.bitsPerSample))
        wav.append(contentsOf: "data".utf8)
        wav.appendLittleEndian(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }

    private static func normalizedSamples(from value: ONNXTensorValue) throws -> [Float] {
        switch value {
        case let .float32(values, shape):
            return try reshape(values: values, shape: shape)
        case let .int32(values, shape):
            return try reshape(
                values: values.map { max(-1.0, min(1.0, Float($0) / Float(Int32.max))) },
                shape: shape
            )
        case let .int64(values, shape):
            return try reshape(
                values: values.map { max(-1.0, min(1.0, Float($0) / Float(Int32.max))) },
                shape: shape
            )
        case .strings:
            throw InferenceWAVWriterError.unsupportedTensorValue
        }
    }

    private static func reshape(values: [Float], shape: [Int]) throws -> [Float] {
        if shape.count == 1 {
            return values
        }
        if shape.count == 2, shape[0] == 1 {
            return values
        }
        if shape.count == 2, shape[1] == 1 {
            return values
        }
        if shape.count == 3, shape[0] == 1, shape[1] == 1 {
            return values
        }
        if shape.count == 3, shape[0] == 1, shape[2] == 1 {
            return values
        }
        throw InferenceWAVWriterError.unsupportedTensorShape(shape)
    }

    private static func clampedSample(_ value: Float) -> Int16 {
        let scaled = max(-1.0, min(1.0, value)) * Float(Int16.max) * 0.82
        return Int16(scaled.rounded())
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private extension Int16 {
    var leBytes: [UInt8] {
        let value = littleEndian
        return [
            UInt8(truncatingIfNeeded: value & 0x00FF),
            UInt8(truncatingIfNeeded: (value >> 8) & 0x00FF),
        ]
    }
}

private struct WAVHeader {
    var sampleRate: Int
    var channelCount: Int
    var bitsPerSample: Int
    var dataRange: Range<Data.Index>
}

private func parseWAVHeader(_ data: Data) throws -> WAVHeader {
    guard data.count >= 44,
          String(decoding: data[0..<4], as: UTF8.self) == "RIFF",
          String(decoding: data[8..<12], as: UTF8.self) == "WAVE",
          String(decoding: data[12..<16], as: UTF8.self) == "fmt ",
          String(decoding: data[36..<40], as: UTF8.self) == "data" else {
        throw InferenceWAVWriterError.invalidWAVData
    }

    let channelCount = Int(littleEndianUInt16(data, at: 22))
    let sampleRate = Int(littleEndianUInt32(data, at: 24))
    let bitsPerSample = Int(littleEndianUInt16(data, at: 34))
    let dataSize = Int(littleEndianUInt32(data, at: 40))
    let dataStart = 44
    let dataEnd = dataStart + dataSize
    guard channelCount > 0,
          sampleRate > 0,
          bitsPerSample == 16,
          dataEnd <= data.count else {
        throw InferenceWAVWriterError.invalidWAVData
    }

    return WAVHeader(
        sampleRate: sampleRate,
        channelCount: channelCount,
        bitsPerSample: bitsPerSample,
        dataRange: dataStart..<dataEnd
    )
}

private func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}
