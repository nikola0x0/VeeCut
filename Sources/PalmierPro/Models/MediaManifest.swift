import Foundation

struct MediaManifest: Codable, Sendable, Equatable {
    var version: Int = 2
    var entries: [MediaManifestEntry] = []
    var folders: [MediaFolder] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        entries = try c.decodeIfPresent([MediaManifestEntry].self, forKey: .entries) ?? []
        folders = try c.decodeIfPresent([MediaFolder].self, forKey: .folders) ?? []
    }

    init() {}

    private enum CodingKeys: String, CodingKey { case version, entries, folders }
}

struct MediaManifestEntry: Codable, Sendable, Equatable, Identifiable {
    let id: String
    var name: String
    var type: ClipType
    var source: MediaSource
    var duration: Double
    var sourceWidth: Int?
    var sourceHeight: Int?
    var sourceFPS: Double?
    var hasAudio: Bool?
    var folderId: String?
    var generationStatus: String?
    var importInput: MediaImportInput?
}

struct MediaImportInput: Codable, Sendable, Equatable {
    var sourceURL: String? = nil
    var sourcePath: String? = nil
    var createdAt: Date? = nil
}

enum MediaSource: Codable, Sendable, Equatable {
    case external(absolutePath: String)
    case project(relativePath: String)
}
