import Foundation
import Testing
@testable import AivisMobileCore

struct ProjectDocumentTests {
    @Test
    func currentFixtureRoundTrips() throws {
        let project = try FixtureBootstrap.loadProjectDocument()

        #expect(project.appVersion == "1.1.0-dev")
        #expect(project.talk.audioKeys == ["audio-1"])
        #expect(project.song.tpqn == 480)

        let migrator = ProjectMigrator()
        let encoded = try migrator.normalizedData(from: project)
        let decodedAgain = try JSONDecoder().decode(AISPProjectDocument.self, from: encoded)
        #expect(decodedAgain == project)
    }

    @Test
    func legacyFixtureMigratesIntoCurrentShape() throws {
        let data = try FixtureBootstrap.loadFixtureData("shared/fixtures/projects/legacy-v0.16.0.aisp.json")
        let project = try ProjectMigrator().migrate(data: data)

        #expect(project.appVersion == "0.16.0")
        #expect(project.talk.audioKeys == ["audio-legacy-1"])
        #expect(project.song == .empty)
    }

    @Test
    func missingPauseLengthScaleDefaultsToDesktopCompatibleValue() throws {
        var project = try FixtureBootstrap.loadProjectDocument()
        project.talk.audioItems["audio-1"]?.query?.pauseLengthScale = 1.35
        let encoded = try JSONEncoder().encode(project)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var talk = try #require(object["talk"] as? [String: Any])
        var audioItems = try #require(talk["audioItems"] as? [String: Any])
        var audioItem = try #require(audioItems["audio-1"] as? [String: Any])
        var query = try #require(audioItem["query"] as? [String: Any])
        query.removeValue(forKey: "pauseLengthScale")
        audioItem["query"] = query
        audioItems["audio-1"] = audioItem
        talk["audioItems"] = audioItems
        object["talk"] = talk

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try ProjectMigrator().migrate(data: data)

        #expect(decoded.talk.audioItems["audio-1"]?.query?.pauseLengthScale == 1.0)
    }

    @Test
    func fileProjectStoreSavesAndLoads() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let targetURL = temporaryDirectory.appendingPathComponent("sample.aisp")
        let original = AISPProjectDocument(
            appVersion: "1.1.0-dev",
            talk: TalkProject(audioKeys: [], audioItems: [:]),
            song: .empty
        )

        let store = FileProjectStore()
        try await store.saveProject(original, to: targetURL)
        let restored = try await store.loadProject(from: targetURL)

        #expect(restored == original)
    }
}
