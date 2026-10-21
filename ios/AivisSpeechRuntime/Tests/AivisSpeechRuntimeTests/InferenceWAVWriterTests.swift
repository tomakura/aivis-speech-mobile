import Foundation
import Testing
@testable import AivisSpeechRuntime

struct InferenceWAVWriterTests {
    @Test
    func waveformTensorConvertsToRiffWave() throws {
        let samples: [Float] = [0.0, 0.2, -0.2, 0.1, -0.1]
        let data = try InferenceWAVWriter.makeWAVData(
            from: .float32(samples, shape: [1, samples.count]),
            sampleRate: 44_100
        )

        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(data.count > 44)
    }

    @Test
    func silentWaveformDoesNotProduceWAV() throws {
        let samples = Array(repeating: Float.zero, count: 512)

        do {
            _ = try InferenceWAVWriter.makeWAVData(
                from: .float32(samples, shape: [1, samples.count]),
                sampleRate: 44_100
            )
            Issue.record("Expected silent waveform conversion to fail.")
        } catch InferenceWAVWriterError.silentWaveform {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
