import Foundation
import Testing
@testable import PalmierPro

@Suite("Bundled skill catalog", .serialized)
@MainActor
struct BundledSkillCatalogTests {
    @Test func everyBundledSkillInstallsFromTheAppBundle() async throws {
        #expect(await SkillCatalog.shared.refresh())
        let entries = SkillCatalog.shared.entries
        #expect(Set(entries.map(\.id)) == [
            "caption-templates", "color-grading", "create-skill-from-timeline", "multi-cam-editing", "ugc-editing",
            "vee-travel-reel", "write-vee-skill",
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

    @Test(arguments: ["vee-travel-reel", "write-vee-skill"])
    func veeSkillsOnlyNameToolsVeeHas(id: String) async throws {
        #expect(await SkillCatalog.shared.refresh())
        let entry = try #require(SkillCatalog.shared.entry(id: id))
        let text = String(decoding: try await SkillCatalog.body(of: entry), as: UTF8.self)
        let named = Set(text.matches(of: /`([a-z]+(?:_[a-z]+)+)`/).map { String($0.output.1) })
        let known = Set(ToolName.allCases.map(\.rawValue))
        #expect(!named.isEmpty)
        #expect(named.subtracting(known).isEmpty, "unknown tools: \(named.subtracting(known).sorted())")
    }

    @Test func bundledSkillsShipWithTheirLicense() async throws {
        let license = try #require(BundledResource.url("Skills/LICENSE"))
        let text = try await Task.detached { try String(contentsOf: license, encoding: .utf8) }.value
        #expect(text.contains("Apache License"))
    }
}
