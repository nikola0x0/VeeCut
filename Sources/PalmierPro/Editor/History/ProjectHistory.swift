import Foundation

/// A saved version of the project after each editor action, kept in the package so history outlives the session.
/// The first version is the base the oldest step undoes back to; each later one belongs to one undo step.
@MainActor
@Observable
final class ProjectHistory {
    struct Version: Identifiable, Sendable {
        enum Content: Sendable {
            case file(ProjectFile)
            /// LZFSE-compressed `ProjectFile` JSON.
            case encoded(Data)
        }

        let id: UUID
        /// The undo history entry this version follows; nil for the base.
        var entryId: UUID?
        let actionName: String
        let date: Date
        /// Tracked masks the version uses, so their files are kept after the live project drops them.
        let maskIds: [String]
        var content: Content

        var byteCount: Int {
            if case .encoded(let data) = content { return data.count }
            return 0
        }

        func projectFile() async throws -> ProjectFile {
            switch content {
            case .file(let file): file
            case .encoded(let data): try await ProjectHistory.decode(data)
            }
        }
    }

    private struct IndexEntry: Codable {
        let id: UUID
        let actionName: String
        let date: Date
        let maskIds: [String]
    }

    nonisolated static let directoryName = "history"
    nonisolated static let indexFileName = "index.json"
    static let maxVersions = 200
    static let maxBytes = 32 * 1024 * 1024

    /// Oldest first.
    private(set) var versions: [Version] = []
    @ObservationIgnored private var pendingEncode: Task<Void, Never>?

    func load(_ versions: [Version]) {
        self.versions = versions
        trim()
    }

    /// Links replayed versions to the undo entries rebuilt for them, oldest first after the base.
    func adopt(entryIds: [UUID]) {
        for (index, entryId) in zip(versions.indices.dropFirst(), entryIds) {
            versions[index].entryId = entryId
        }
    }

    /// What a save keeps: the base, then the versions of the applied entries in undo order.
    func savedVersions(applied entryIds: [UUID]) -> [Version] {
        let byEntry = Dictionary(versions.compactMap { version in version.entryId.map { ($0, version) } }) { first, _ in first }
        let base = versions.first.flatMap { $0.entryId == nil ? $0 : nil }
        return (base.map { [$0] } ?? []) + entryIds.compactMap { byEntry[$0] }
    }

    /// The state undo starts from when there is no saved history yet.
    func recordBase(_ file: ProjectFile) {
        guard versions.isEmpty else { return }
        record(actionName: String(), entryId: nil, file: file, liveEntryIds: [])
    }

    /// Keeps the project as it is after an undo entry, dropping versions of entries undo has discarded.
    /// Compression runs off the main actor in commit order.
    func record(actionName: String, entryId: UUID?, file: ProjectFile, liveEntryIds: Set<UUID>) {
        versions.removeAll { version in version.entryId.map { !liveEntryIds.contains($0) } ?? false }
        let version = Version(
            id: UUID(), entryId: entryId, actionName: actionName, date: .now,
            maskIds: (file.trackedMasks ?? []).map(\.id), content: .file(file)
        )
        versions.append(version)
        trim()
        let previous = pendingEncode
        pendingEncode = Task { [weak self] in
            await previous?.value
            do {
                let data = try await Self.encode(file)
                self?.replaceContent(of: version.id, with: data)
            } catch {
                Log.project.error("history encode failed action=\(actionName) error=\(String(describing: error))")
            }
        }
    }

    /// Resolves once every recorded version is compressed.
    func encodingFinished() async {
        await pendingEncode?.value
    }

    private func replaceContent(of id: UUID, with data: Data) {
        guard let index = versions.firstIndex(where: { $0.id == id }) else { return }
        versions[index].content = .encoded(data)
        trim()
    }

    /// Drops the oldest versions past the count or size limit, always keeping the newest.
    private func trim() {
        var bytes = versions.reduce(0) { $0 + $1.byteCount }
        while versions.count > 1, versions.count > Self.maxVersions || bytes > Self.maxBytes {
            bytes -= versions.removeFirst().byteCount
        }
    }

    // MARK: - Encoding

    @concurrent
    static func encode(_ file: ProjectFile) async throws -> Data {
        try encodeNow(file)
    }

    @concurrent
    static func decode(_ data: Data) async throws -> ProjectFile {
        try ProjectFile.decode(try (data as NSData).decompressed(using: .lzfse) as Data)
    }

    nonisolated private static func encodeNow(_ file: ProjectFile) throws -> Data {
        try (JSONEncoder().encode(file) as NSData).compressed(using: .lzfse) as Data
    }

    // MARK: - Package files

    nonisolated private static func versionFileName(_ id: UUID) -> String { "\(id.uuidString).json.lzfse" }
    nonisolated private static func maskFileName(_ maskId: String) -> String { "mask-\(TrackedMaskFile.fileName(maskId: maskId))" }

    /// The history directory's files: an index, one file per version, and the mask files versions use.
    /// Runs off the main actor during save; versions still uncompressed are compressed here.
    nonisolated static func packageFiles(_ versions: [Version], maskFiles: [String: Data]) throws -> [(name: String, data: Data)] {
        guard !versions.isEmpty else { return [] }
        var files: [(name: String, data: Data)] = []
        for version in versions {
            let data = switch version.content {
            case .encoded(let data): data
            case .file(let file): try encodeNow(file)
            }
            files.append((versionFileName(version.id), data))
        }
        let index = versions.map { IndexEntry(id: $0.id, actionName: $0.actionName, date: $0.date, maskIds: $0.maskIds) }
        files.append((indexFileName, try JSONEncoder().encode(index)))
        for maskId in Set(versions.flatMap(\.maskIds)).sorted() {
            if let data = maskFiles[maskId] { files.append((maskFileName(maskId), data)) }
        }
        return files
    }

    /// Reads the history directory; a missing or unreadable index means no history, never a failed open.
    nonisolated static func read(_ file: (String) throws -> Data?) -> (versions: [Version], maskFiles: [String: Data]) {
        do {
            guard let indexData = try file(indexFileName) else { return ([], [:]) }
            let index = try JSONDecoder().decode([IndexEntry].self, from: indexData)
            var versions: [Version] = []
            for entry in index {
                guard let data = try file(versionFileName(entry.id)) else { continue }
                versions.append(Version(id: entry.id, entryId: nil, actionName: entry.actionName, date: entry.date,
                                        maskIds: entry.maskIds, content: .encoded(data)))
            }
            var maskFiles: [String: Data] = [:]
            for maskId in Set(index.flatMap(\.maskIds)) {
                if let data = try file(maskFileName(maskId)) { maskFiles[maskId] = data }
            }
            return (versions, maskFiles)
        } catch {
            Log.project.error("history read failed error=\(String(describing: error))")
            return ([], [:])
        }
    }
}
