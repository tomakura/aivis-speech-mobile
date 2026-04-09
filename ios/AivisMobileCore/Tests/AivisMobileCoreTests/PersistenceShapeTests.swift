import Foundation
import Testing
@testable import AivisMobileCore

struct PersistenceShapeTests {
    @Test
    func presetFixtureDecodes() throws {
        let catalog = try FixtureBootstrap.loadPresetCatalog()

        #expect(catalog.keys == ["default-normal"])
        #expect(catalog.items["default-normal"]?.name == "Normal")
    }

    @Test
    func dictionaryFixtureDecodes() throws {
        let dictionary = try FixtureBootstrap.loadDictionary()

        #expect(dictionary.entries.count == 1)
        #expect(dictionary.entries.first?.surface == "琴葉")
    }

    @Test
    func defaultStyleFixtureDecodes() throws {
        let styles = try FixtureBootstrap.loadDefaultStyles()

        #expect(styles.count == 1)
        #expect(styles.first?.defaultStyleID == 888753760)
    }
}
