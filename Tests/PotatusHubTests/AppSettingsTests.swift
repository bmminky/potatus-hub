import XCTest
@testable import PotatusHub

final class AppSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "PotatusHubTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testStorageKeysAreUnchanged() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.setVisible(false, kind: .gpu)
        settings.language = .korean
        settings.saveGroups([], shadowMargin: 18)
        XCTAssertEqual(defaults.object(forKey: "PotatusHub.visible.gpu") as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: "PotatusHub.languagePreference"), "korean")
        XCTAssertNotNil(defaults.data(forKey: "PotatusHub.groups.v1"))
        XCTAssertEqual(defaults.double(forKey: "PotatusHub.savedShadowMargin"), 18)
    }

    func testDefaults() {
        let settings = AppSettings(defaults: makeDefaults())
        XCTAssertTrue(settings.isVisible(.ram))
        XCTAssertEqual(settings.language, .system)
        XCTAssertNil(settings.loadGroups())
        XCTAssertEqual(settings.savedShadowMargin, 14)
        XCTAssertNil(settings.legacyFrame(for: .cpu))
    }

    func testReadsGroupsSavedInExistingFormat() throws {
        let defaults = makeDefaults()
        // Shape written by earlier versions (layout is optional).
        let json = #"[{"kinds":["ram","cpu"],"axis":"horizontal","frame":"{{10, 20}, {364, 114}}"}]"#
        defaults.set(Data(json.utf8), forKey: "PotatusHub.groups.v1")
        defaults.set("{{5, 6}, {100, 80}}", forKey: "PotatusHub.frame.gpu")
        let settings = AppSettings(defaults: defaults)
        let groups = try XCTUnwrap(settings.loadGroups())
        XCTAssertEqual(groups.first?.kinds, [.ram, .cpu])
        XCTAssertEqual(groups.first?.axis, .horizontal)
        XCTAssertNil(groups.first?.layout)
        XCTAssertEqual(settings.legacyFrame(for: .gpu)?.origin, CGPoint(x: 5, y: 6))
    }
}
