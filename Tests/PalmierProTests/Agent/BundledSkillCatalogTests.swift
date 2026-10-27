import Foundation
import Testing
@testable import PalmierPro

@Suite("Bundled skill catalog")
@MainActor
struct BundledSkillCatalogTests {
    @Test func everyBundledSkillInstallsFromTheAppBundle() async throws {
        #expect(await SkillCatalog.shared.refresh())
        let entries = SkillCatalog.shared.entries
        #expect(Set(entries.map(\.id)) == [
            "caption-templates", "color-grading", "create-skill-from-timeline", "multi-cam-editing", "ugc-editing",
        ])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("veecut-bundled-skills-\(UUID().uuidString)", isDirectory: true)
        let store = SkillStore(directory: directory)
        await store.reloadSkills()
        for entry in entries {
            #expect(await store.install(entry), "\(entry.id) should install")
        }
        #expect(Set(store.skills.map(\.id)) == Set(entries.map(\.id)))
        #expect(entries.allSatisfy { store.origin(for: $0.id) == .community })
        await Task.detached { try? FileManager.default.removeItem(at: directory) }.value
    }

    @Test func bundledSkillsShipWithTheirLicense() async throws {
        let license = try #require(BundledResource.url("Skills/LICENSE"))
        let text = try await Task.detached { try String(contentsOf: license, encoding: .utf8) }.value
        #expect(text.contains("Apache License"))
    }
}
