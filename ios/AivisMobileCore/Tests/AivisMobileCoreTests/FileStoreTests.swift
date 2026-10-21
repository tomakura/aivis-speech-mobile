import Foundation
import Testing
@testable import AivisMobileCore

struct FileStoreTests {
    @Test
    func presetAndDefaultStylesStoreRoundTrips() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let presetURL = temporaryDirectory.appendingPathComponent("presets.json")
        let defaultStylesURL = temporaryDirectory.appendingPathComponent("default-styles.json")
        let store = FilePresetStore(
            presetCatalogURL: presetURL,
            defaultStylesURL: defaultStylesURL
        )

        let catalog = try FixtureBootstrap.loadPresetCatalog()
        let defaultStyles = try FixtureBootstrap.loadDefaultStyles()

        try await store.savePresetCatalog(catalog)
        try await store.saveDefaultStyles(defaultStyles)

        #expect(try await store.loadPresetCatalog() == catalog)
        #expect(try await store.loadDefaultStyles() == defaultStyles)
    }

    @Test
    func dictionaryStoreRoundTrips() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let dictionaryURL = temporaryDirectory.appendingPathComponent("dictionary.json")
        let store = FileDictionaryStore(fileURL: dictionaryURL)
        let dictionary = try FixtureBootstrap.loadDictionary()

        try await store.saveDictionary(dictionary)
        #expect(try await store.loadDictionary() == dictionary)
    }
}

