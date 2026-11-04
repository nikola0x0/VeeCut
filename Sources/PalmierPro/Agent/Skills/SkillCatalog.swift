import Foundation

/// One entry in the bundled catalog.json. `sha` is a content hash of the SKILL.md
/// and is the version anchor: a changed sha means an update is available.
struct SkillCatalogEntry: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let sha: String
    let path: String
}

enum SkillCatalogError: Error {
    case missingResource(String)
}

/// Skills bundled under Resources/Skills: VeeCut's own (vee-travel-reel, write-vee-skill) and five from palmier-io/palmier-skills (Apache-2.0).
@Observable
@MainActor
final class SkillCatalog {
    static let shared = SkillCatalog()

    nonisolated private static let resourceDirectory = "Skills"

    private(set) var entries: [SkillCatalogEntry] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    private init() {}

    func entry(id: String) -> SkillCatalogEntry? { entries.first { $0.id == id } }

    @discardableResult
    func refresh() async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await Self.resource("catalog.json")
            entries = try JSONDecoder().decode([SkillCatalogEntry].self, from: data)
            lastError = nil
            return true
        } catch {
            lastError = L10n.string("The bundled skills could not be loaded.")
            Log.agent.error("skill catalog load failed: \(String(describing: error))")
            return false
        }
    }

    @concurrent
    static func body(of entry: SkillCatalogEntry) async throws -> Data {
        try await resource(entry.path)
    }

    @concurrent
    private static func resource(_ path: String) async throws -> Data {
        let relative = "\(resourceDirectory)/\(path)"
        guard !path.split(separator: "/").contains(".."),
              let url = BundledResource.url(relative) else { throw SkillCatalogError.missingResource(relative) }
        return try Data(contentsOf: url)
    }
}
