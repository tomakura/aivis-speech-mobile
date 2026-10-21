import Foundation

public enum FixtureBootstrapError: Error, LocalizedError {
    case repositoryRootNotFound

    public var errorDescription: String? {
        switch self {
        case .repositoryRootNotFound:
            return "Could not locate the repository root for shared fixtures."
        }
    }
}

public enum FixtureBootstrap {
    private static let repositoryMarker = "shared"

    public static func repositoryRoot(startingFrom filePath: StaticString = #filePath) throws -> URL {
        var url = URL(fileURLWithPath: "\(filePath)")
        while url.path != "/" {
            let markerURL = url.appendingPathComponent(repositoryMarker)
            if FileManager.default.fileExists(atPath: markerURL.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw FixtureBootstrapError.repositoryRootNotFound
    }

    public static func fixtureURL(
        _ relativePath: String,
        startingFrom filePath: StaticString = #filePath
    ) throws -> URL {
        try repositoryRoot(startingFrom: filePath).appendingPathComponent(relativePath)
    }

    public static func loadFixtureData(
        _ relativePath: String,
        startingFrom filePath: StaticString = #filePath
    ) throws -> Data {
        try Data(contentsOf: fixtureURL(relativePath, startingFrom: filePath))
    }

    public static func loadProjectDocument(
        _ relativePath: String = "shared/fixtures/projects/current-v1.1.0-dev.aisp.json",
        startingFrom filePath: StaticString = #filePath
    ) throws -> AISPProjectDocument {
        let data = try loadFixtureData(relativePath, startingFrom: filePath)
        return try ProjectMigrator().migrate(data: data)
    }

    public static func loadPresetCatalog(
        _ relativePath: String = "shared/fixtures/settings/presets.json",
        startingFrom filePath: StaticString = #filePath
    ) throws -> PresetCatalog {
        try JSONDecoder().decode(
            PresetCatalog.self,
            from: loadFixtureData(relativePath, startingFrom: filePath)
        )
    }

    public static func loadDictionary(
        _ relativePath: String = "shared/fixtures/settings/dictionary.json",
        startingFrom filePath: StaticString = #filePath
    ) throws -> UserDictionary {
        try JSONDecoder().decode(
            UserDictionary.self,
            from: loadFixtureData(relativePath, startingFrom: filePath)
        )
    }

    public static func loadDefaultStyles(
        _ relativePath: String = "shared/fixtures/settings/default-styles.json",
        startingFrom filePath: StaticString = #filePath
    ) throws -> [DefaultStyleID] {
        try JSONDecoder().decode(
            [DefaultStyleID].self,
            from: loadFixtureData(relativePath, startingFrom: filePath)
        )
    }

    public static func loadAIVMXMetadataEnvelope(
        _ relativePath: String = "shared/fixtures/models/aivmx-metadata.sample.json",
        startingFrom filePath: StaticString = #filePath
    ) throws -> AIVMXMetadataEnvelope {
        try JSONDecoder().decode(
            AIVMXMetadataEnvelope.self,
            from: loadFixtureData(relativePath, startingFrom: filePath)
        )
    }
}
