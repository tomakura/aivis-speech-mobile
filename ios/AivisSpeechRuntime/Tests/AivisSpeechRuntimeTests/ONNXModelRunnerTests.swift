import Foundation
import Testing
@testable import AivisSpeechRuntime

struct ONNXModelRunnerTests {
    @Test
    func sampleSeedModelRunsAddInference() throws {
        let modelURL = try #require(
            Bundle.module.url(forResource: "sample_runtime_seed", withExtension: "onnx")
        )

        let outputs = try ONNXModelRunner.run(
            modelURL: modelURL,
            inputs: [
                "A": .float32([1.25], shape: [1]),
                "B": .float32([2.75], shape: [1]),
            ],
            outputNames: ["C"],
            preferCoreML: false
        )

        guard case let .float32(values, shape)? = outputs["C"] else {
            Issue.record("Expected float32 tensor output named C.")
            return
        }

        #expect(shape == [1])
        #expect(values.count == 1)
        #expect(abs(values[0] - 4.0) < 0.0001)
    }
}
