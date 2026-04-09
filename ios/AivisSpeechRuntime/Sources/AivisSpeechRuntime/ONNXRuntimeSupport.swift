import Foundation
import AivisMobileCore
import OnnxRuntimeBindings

public enum ONNXRuntimeSupportError: LocalizedError {
    case environmentCreationFailed(String)
    case sessionOptionsCreationFailed(String)
    case coreMLEnablementFailed(String)
    case sessionCreationFailed(String)
    case modelInspectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .environmentCreationFailed(message):
            return "Failed to create ORTEnv: \(message)"
        case let .sessionOptionsCreationFailed(message):
            return "Failed to create ORTSessionOptions: \(message)"
        case let .coreMLEnablementFailed(message):
            return "Failed to enable CoreML Execution Provider: \(message)"
        case let .sessionCreationFailed(message):
            return "Failed to create ORTSession: \(message)"
        case let .modelInspectionFailed(message):
            return "Failed to inspect the ONNX model: \(message)"
        }
    }
}

public struct ONNXModelInspection: Sendable, Equatable {
    public var inputNames: [String]
    public var outputNames: [String]

    public init(inputNames: [String], outputNames: [String]) {
        self.inputNames = inputNames
        self.outputNames = outputNames
    }
}

public enum ONNXRuntimeSupport {
    public static let sharedSessionCache = ONNXSessionCache(maxEntriesPerModelURL: 1)

    private static var supportsAppleNeuralEngine: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    public static func statusSnapshot() -> EngineRuntimeStatus {
        let coreMLAvailable = ORTIsCoreMLExecutionProviderAvailable()
        let notes = [
            coreMLAvailable ? "CoreML EP available" : "CoreML EP unavailable, CPU fallback only",
            supportsAppleNeuralEngine ? "Apple Neural Engine preferred" : "Apple Neural Engine unavailable in this runtime",
            "Runtime layer isolated in ios/AivisSpeechRuntime",
        ]

        return EngineRuntimeStatus(
            providerName: "ONNX Runtime Mobile",
            availability: .linked,
            preferredExecutionProvider: coreMLAvailable ? "CoreML Execution Provider" : "CPU fallback",
            linkedVersion: ORTVersion(),
            coreMLAvailable: coreMLAvailable,
            notes: notes
        )
    }

    public static func supportedDevices() -> SupportedDevices {
        let status = statusSnapshot()
        return SupportedDevices(
            cpu: true,
            gpu: false,
            neuralEnginePreferred: status.coreMLAvailable && supportsAppleNeuralEngine,
            coreML: status.coreMLAvailable
        )
    }

    public static func makeEnvironment(
        loggingLevel: ORTLoggingLevel = .warning
    ) throws -> ORTEnv {
        do {
            return try ORTEnv(loggingLevel: loggingLevel)
        } catch {
            throw ONNXRuntimeSupportError.environmentCreationFailed(error.localizedDescription)
        }
    }

    public static func makeSessionOptions(
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false
    ) throws -> ORTSessionOptions {
        let sessionOptions: ORTSessionOptions
        do {
            sessionOptions = try ORTSessionOptions()
        } catch {
            throw ONNXRuntimeSupportError.sessionOptionsCreationFailed(error.localizedDescription)
        }

        do {
            try sessionOptions.setGraphOptimizationLevel(.all)
            try sessionOptions.setIntraOpNumThreads(0)
            try sessionOptions.setLogSeverityLevel(.warning)
            try sessionOptions.setLogID("aivis.mobile.runtime")
            try sessionOptions.addConfigEntry(
                withKey: "session.intra_op.allow_spinning",
                value: "1"
            )
        } catch {
            throw ONNXRuntimeSupportError.sessionOptionsCreationFailed(error.localizedDescription)
        }

        guard preferCoreML, ORTIsCoreMLExecutionProviderAvailable() else {
            return sessionOptions
        }

        let coreMLOptions = ORTCoreMLExecutionProviderOptions()
        coreMLOptions.useCPUOnly = false
        coreMLOptions.useCPUAndGPU = false
        coreMLOptions.enableOnSubgraphs = true
        coreMLOptions.onlyEnableForDevicesWithANE = supportsAppleNeuralEngine
        coreMLOptions.onlyAllowStaticInputShapes = staticInputShapesOnly
        coreMLOptions.createMLProgram = true

        do {
            try sessionOptions.appendCoreMLExecutionProvider(with: coreMLOptions)
        } catch {
            throw ONNXRuntimeSupportError.coreMLEnablementFailed(error.localizedDescription)
        }

        return sessionOptions
    }

    public static func makeSessionHandle(
        modelURL: URL,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar
    ) throws -> ONNXSessionHandle {
        let env = try makeEnvironment()
        let sessionOptions = try makeSessionOptions(
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly
        )

        do {
            let session = try ORTSession(
                env: env,
                modelPath: modelURL.path,
                sessionOptions: sessionOptions
            )
            let providerName = preferCoreML && ORTIsCoreMLExecutionProviderAvailable()
                ? "CoreML Execution Provider"
                : "CPU fallback"
            return ONNXSessionHandle(
                modelURL: modelURL,
                preferredExecutionProvider: providerName,
                staticInputShapesOnly: staticInputShapesOnly,
                shapeProfile: shapeProfile,
                scalarInputMode: scalarInputMode,
                environment: env,
                liveSession: session
            )
        } catch {
            throw ONNXRuntimeSupportError.sessionCreationFailed(error.localizedDescription)
        }
    }

    public static func makeBestEffortSessionHandle(
        modelURL: URL,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar
    ) throws -> ONNXSessionHandle {
        do {
            return try makeSessionHandle(
                modelURL: modelURL,
                preferCoreML: preferCoreML,
                staticInputShapesOnly: staticInputShapesOnly,
                shapeProfile: shapeProfile,
                scalarInputMode: scalarInputMode
            )
        } catch {
            guard preferCoreML else { throw error }
            return try makeSessionHandle(
                modelURL: modelURL,
                preferCoreML: false,
                staticInputShapesOnly: false,
                shapeProfile: shapeProfile,
                scalarInputMode: scalarInputMode
            )
        }
    }

    public static func makeSession(
        modelURL: URL,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar
    ) throws -> ORTSession {
        try makeBestEffortSessionHandle(
            modelURL: modelURL,
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode
        ).liveSessionValue()
    }

    public static func cachedSessionHandle(
        for modelURL: URL,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar
    ) throws -> ONNXSessionHandle {
        try sharedSessionCache.sessionHandle(
            for: modelURL,
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode
        )
    }

    public static func cachedSession(
        for modelURL: URL,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar
    ) throws -> ORTSession {
        try cachedSessionHandle(
            for: modelURL,
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode
        ).liveSessionValue()
    }

    public static func inspectModel(
        at modelURL: URL,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar
    ) throws -> ONNXModelInspection {
        try cachedSessionHandle(
            for: modelURL,
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode
        ).inspectModel()
    }
}
