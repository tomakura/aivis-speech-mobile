import Foundation
import AivisMobileCore
import OnnxRuntimeBindings

public final class ONNXSessionHandle: @unchecked Sendable {
    public let modelURL: URL
    public let preferredExecutionProvider: String
    public let staticInputShapesOnly: Bool
    public let shapeProfile: StaticShapeProfile?
    public let scalarInputMode: ScalarInputMode
    public let createdAt: Date
    public private(set) var lastAccessedAt: Date
    public var isLiveSession: Bool { liveSession != nil }
    public var bootstrapSummary: ONNXSessionBootstrap {
        ONNXSessionBootstrap(
            modelURL: modelURL,
            preferredExecutionProvider: preferredExecutionProvider,
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt,
            isLiveSession: isLiveSession
        )
    }

    private let environment: ORTEnv?
    private let liveSession: ORTSession?

    public static func placeholder(
        modelURL: URL,
        preferredExecutionProvider: String = "placeholder",
        staticInputShapesOnly: Bool = false,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar
    ) -> ONNXSessionHandle {
        ONNXSessionHandle(
            modelURL: modelURL,
            preferredExecutionProvider: preferredExecutionProvider,
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode
        )
    }

    public func touch() {
        lastAccessedAt = Date()
    }

    internal func liveSessionValue() throws -> ORTSession {
        guard let liveSession else {
            throw ONNXRuntimeSupportError.sessionCreationFailed("Session handle is placeholder-only.")
        }
        return liveSession
    }

    internal func inspectModel() throws -> ONNXModelInspection {
        let session = try liveSessionValue()
        do {
            let inputNames = try session.inputNames()
            let outputNames = try session.outputNames()
            return ONNXModelInspection(inputNames: inputNames, outputNames: outputNames)
        } catch {
            throw ONNXRuntimeSupportError.modelInspectionFailed(error.localizedDescription)
        }
    }

    internal init(
        modelURL: URL,
        preferredExecutionProvider: String,
        staticInputShapesOnly: Bool,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar,
        createdAt: Date = Date(),
        environment: ORTEnv? = nil,
        liveSession: ORTSession? = nil
    ) {
        self.modelURL = modelURL
        self.preferredExecutionProvider = preferredExecutionProvider
        self.staticInputShapesOnly = staticInputShapesOnly
        self.shapeProfile = shapeProfile
        self.scalarInputMode = scalarInputMode
        self.createdAt = createdAt
        self.lastAccessedAt = createdAt
        self.environment = environment
        self.liveSession = liveSession
    }
}

public struct ONNXSessionBootstrap: Sendable, Equatable {
    public var modelURL: URL
    public var preferredExecutionProvider: String
    public var staticInputShapesOnly: Bool
    public var shapeProfile: StaticShapeProfile?
    public var scalarInputMode: ScalarInputMode
    public var createdAt: Date
    public var lastAccessedAt: Date
    public var isLiveSession: Bool

    public init(
        modelURL: URL,
        preferredExecutionProvider: String,
        staticInputShapesOnly: Bool,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar,
        createdAt: Date,
        lastAccessedAt: Date,
        isLiveSession: Bool
    ) {
        self.modelURL = modelURL
        self.preferredExecutionProvider = preferredExecutionProvider
        self.staticInputShapesOnly = staticInputShapesOnly
        self.shapeProfile = shapeProfile
        self.scalarInputMode = scalarInputMode
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.isLiveSession = isLiveSession
    }

    public var modeLabel: String {
        isLiveSession ? "live" : "cached"
    }

    public var shapeLabel: String {
        shapeProfile?.shapeLabel ?? (staticInputShapesOnly ? "static-unspecified" : "dynamic")
    }
}

public final class ONNXSessionCache: @unchecked Sendable {
    public struct SessionKey: Hashable, Sendable {
        public var modelURL: URL
        public var preferCoreML: Bool
        public var staticInputShapesOnly: Bool
        public var shapeProfile: StaticShapeProfile?
        public var scalarInputMode: ScalarInputMode

        public init(
            modelURL: URL,
            preferCoreML: Bool,
            staticInputShapesOnly: Bool,
            shapeProfile: StaticShapeProfile? = nil,
            scalarInputMode: ScalarInputMode = .rank0Scalar
        ) {
            self.modelURL = modelURL
            self.preferCoreML = preferCoreML
            self.staticInputShapesOnly = staticInputShapesOnly
            self.shapeProfile = shapeProfile
            self.scalarInputMode = scalarInputMode
        }
    }

    private struct CacheEntry {
        var handle: ONNXSessionHandle
    }

    private let lock = NSLock()
    private var entries: [SessionKey: CacheEntry]
    private let maxEntriesPerModelURL: Int?
    private let sessionFactory: (URL, Bool, Bool, StaticShapeProfile?, ScalarInputMode) throws -> ONNXSessionHandle

    public init(
        maxEntriesPerModelURL: Int? = nil,
        sessionFactory: @escaping (URL, Bool, Bool, StaticShapeProfile?, ScalarInputMode) throws -> ONNXSessionHandle = ONNXRuntimeSupport.makeBestEffortSessionHandle
    ) {
        self.entries = [:]
        self.maxEntriesPerModelURL = maxEntriesPerModelURL
        self.sessionFactory = sessionFactory
    }

    public func sessionHandle(
        for modelURL: URL,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar
    ) throws -> ONNXSessionHandle {
        let key = SessionKey(
            modelURL: modelURL,
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode
        )

        lock.lock()
        if let entry = entries[key] {
            entry.handle.touch()
            let handle = entry.handle
            lock.unlock()
            return handle
        }
        lock.unlock()

        let handle = try sessionFactory(modelURL, preferCoreML, staticInputShapesOnly, shapeProfile, scalarInputMode)

        lock.lock()
        entries[key] = CacheEntry(handle: handle)
        evictEntriesIfNeeded(keeping: key)
        lock.unlock()
        return handle
    }

    public func cachedSessionCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    public func cachedModelURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return entries.keys.map(\.modelURL).sorted { $0.absoluteString < $1.absoluteString }
    }

    public func invalidateSession(
        for modelURL: URL,
        preferCoreML: Bool = true,
        staticInputShapesOnly: Bool = false,
        shapeProfile: StaticShapeProfile? = nil,
        scalarInputMode: ScalarInputMode = .rank0Scalar
    ) {
        let key = SessionKey(
            modelURL: modelURL,
            preferCoreML: preferCoreML,
            staticInputShapesOnly: staticInputShapesOnly,
            shapeProfile: shapeProfile,
            scalarInputMode: scalarInputMode
        )
        lock.lock()
        entries.removeValue(forKey: key)
        lock.unlock()
    }

    public func invalidateSessions(for modelURL: URL) {
        lock.lock()
        entries = entries.filter { key, _ in
            key.modelURL != modelURL
        }
        lock.unlock()
    }

    public func invalidateAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    private func evictEntriesIfNeeded(keeping keyToKeep: SessionKey) {
        guard let maxEntriesPerModelURL, maxEntriesPerModelURL > 0 else {
            return
        }
        let matchingEntries = entries.filter { key, _ in
            key.modelURL == keyToKeep.modelURL
        }
        guard matchingEntries.count > maxEntriesPerModelURL else {
            return
        }

        let evictionKeys = matchingEntries
            .filter { key, _ in key != keyToKeep }
            .sorted { lhs, rhs in
                lhs.value.handle.lastAccessedAt < rhs.value.handle.lastAccessedAt
            }
            .prefix(matchingEntries.count - maxEntriesPerModelURL)
            .map(\.key)
        for key in evictionKeys {
            entries.removeValue(forKey: key)
        }
    }
}

public struct ONNXSessionInspection {
    public var handle: ONNXSessionHandle

    public init(handle: ONNXSessionHandle) {
        self.handle = handle
    }
}
