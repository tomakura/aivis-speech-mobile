import Foundation
import Testing
@testable import AivisSpeechRuntime

@Test
func placeholderSessionsAreCachedByKey() throws {
    let modelURL = URL(fileURLWithPath: "/tmp/sample.aivmx")
    let cache = ONNXSessionCache { url, preferCoreML, staticInputShapesOnly, shapeProfile, scalarInputMode in
        ONNXSessionHandle.placeholder(
            modelURL: url,
            preferredExecutionProvider: preferCoreML ? "CoreML Execution Provider" : "CPU fallback",
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode
        )
    }

    let first = try cache.sessionHandle(for: modelURL, preferCoreML: true, staticInputShapesOnly: false)
    let second = try cache.sessionHandle(for: modelURL, preferCoreML: true, staticInputShapesOnly: false)

    #expect(first === second)
    #expect(cache.cachedSessionCount() == 1)
    #expect(cache.cachedModelURLs() == [modelURL])
}

@Test
func cacheInvalidationDropsEntries() throws {
    let modelURL = URL(fileURLWithPath: "/tmp/sample.aivmx")
    let cache = ONNXSessionCache { url, preferCoreML, staticInputShapesOnly, shapeProfile, scalarInputMode in
        ONNXSessionHandle.placeholder(
            modelURL: url,
            preferredExecutionProvider: preferCoreML ? "CoreML Execution Provider" : "CPU fallback",
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode
        )
    }

    _ = try cache.sessionHandle(for: modelURL)
    cache.invalidateSession(for: modelURL)

    #expect(cache.cachedSessionCount() == 0)
}

@Test
func bootstrapSummaryDescribesSessionState() {
    let modelURL = URL(fileURLWithPath: "/tmp/sample.aivmx")
    let profile = StaticShapeProfile(
        label: "bert-32",
        dimensions: [.init(name: "sequence_length", value: 32)]
    )
    let handle = ONNXSessionHandle.placeholder(
        modelURL: modelURL,
        preferredExecutionProvider: "CPU fallback",
        staticInputShapesOnly: true,
        shapeProfile: profile
    )

    let summary = handle.bootstrapSummary

    #expect(summary.modelURL == modelURL)
    #expect(summary.modeLabel == "cached")
    #expect(summary.preferredExecutionProvider == "CPU fallback")
    #expect(summary.staticInputShapesOnly)
    #expect(summary.shapeProfile == profile)
    #expect(summary.shapeLabel == "bert-32")
    #expect(!summary.isLiveSession)
}
