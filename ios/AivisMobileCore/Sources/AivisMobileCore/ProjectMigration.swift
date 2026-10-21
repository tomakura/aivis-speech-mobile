import Foundation

public enum ProjectMigrationError: Error, LocalizedError, Equatable {
    case invalidPayload
    case unsupportedShape

    public var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "The project payload could not be decoded."
        case .unsupportedShape:
            return "The project shape is not supported by the migrator."
        }
    }
}

private struct LegacyProjectV016: Codable, Equatable {
    var appVersion: String
    var audioKeys: [String]
    var audioItems: [String: AudioItem]
}

public struct ProjectMigrator: Sendable {
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(decoder: JSONDecoder = JSONDecoder(), encoder: JSONEncoder = JSONEncoder()) {
        self.decoder = decoder
        self.encoder = encoder
    }

    public func migrate(data: Data) throws -> AISPProjectDocument {
        if let current = try? decoder.decode(AISPProjectDocument.self, from: data) {
            return current
        }

        if let legacy = try? decoder.decode(LegacyProjectV016.self, from: data) {
            return AISPProjectDocument(
                appVersion: legacy.appVersion,
                talk: TalkProject(audioKeys: legacy.audioKeys, audioItems: legacy.audioItems),
                song: .empty
            )
        }

        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw ProjectMigrationError.invalidPayload
        }
        throw ProjectMigrationError.unsupportedShape
    }

    public func normalizedData(from project: AISPProjectDocument) throws -> Data {
        try encoder.encode(project)
    }
}

